#include <stdlib.h>
#include <stdio.h>
#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"

module TCPP {
    provides interface TCP;
    //Interfaces 
    uses interface Timer<TMilli> as PacketTimer;
    uses interface Hashmap<socket_store_t> as SocketMap;
    uses interface List<socket_store_t> as ServerList;
    uses interface List<pack> as CurrentMessages;    
}

implementation {
    //General verilables
    socket_t next_fd = 1;   //next available file dicripter
    uint16_t* node_seq;     //Node sequence number 
    const uint16_t default_rtt = 200;    //default rount trip time
    uint8_t temp_buffer[TCP_PAYLOAD_SIZE]; // buffer to store payload
    

    //uint8_t myData[] = "Hello, TinyOS!";
   // uint16_t dataSize = sizeof(myData) - 1;  // Exclude the null terminator


    void sendSyn(socket_t socketFD);
    void sendAck(socket_t socketFD, pack* original_message);
    void sendFin(socket_t socketFD);
    void sendDat(socket_t socketFD, uint8_t* data, uint16_t size);

    void send(socket_t socketFD, uint32_t transfer);
    void write(socket_t socketFD, pack* msg);
    void sendNext();
    void sendNextFromSocket(socket_t socketFD);

    socket_t getNextFD();
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    socket_t addSocket(socket_store_t socket);
    void updateState(socket_t socketFD, enum socket_state new_state);
    void updateSocket(socket_t socketFD, socket_store_t new_socket);
    void getState(enum socket_state state, char* str);

     ////////////////////////////////// getNextFD /////////////////////////////////
    // Finds the next available file descriptor for a new socket
    socket_t getNextFD() {
        uint32_t* fds = call SocketMap.getKeys(); 
        uint16_t size = call SocketMap.size();
        socket_t fd = 1;
        uint8_t i;

        for (fd = 1; fd > 0; fd++) {
            bool found = FALSE;
            for (i = 0; i < size; i++) {
                if (fd != (socket_t)fds[i]) {
                    found = TRUE;
                }
            }

            if (!found) {
                //return available file discripter
                return fd;
            }      
        }

        dbg(TRANSPORT_CHANNEL, "[Error] getNextFD: No valid file descriptor found\n");
        return 0;
    }

    ////////////////////////////////// getFD /////////////////////////////////
    // Retrieves the socket file descriptor for a given destination and port
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        uint32_t* fds = call SocketMap.getKeys();
        uint16_t size = call SocketMap.size();
        uint16_t i;

        // Loop through existing sockets to find a match
        for (i = 0; i < size; i++) {
            socket_t socketFD = fds[i];
            socket_store_t socket = call SocketMap.get(socketFD);

            if (socket.src == srcPort &&
                socket.dest.port == destPort &&
                socket.dest.addr == dest) {
                    return socketFD;
            }
        }

        dbg(TRANSPORT_CHANNEL, "[Error] getFD: File descriptor not found for dest: %hu, srcPort: %hhu, destPort: %hhu\n", dest, srcPort, destPort);
        return 0;
    }

    ////////////////////////////////// State of the socket /////////////////////////////////
    // what is the sate of the socket using switch statement
    void getState(enum socket_state state, char* str) {
        switch(state) {
            case CLOSED:
                str = "CLOSED";
                break;
            case LISTEN:
                str = "LISTEN";
                break;
            case ESTABLISHED:
                str = "ESTABLISHED";
                break;
            case SYN_SENT:
                str = "SYN_SENT";
                break;
            case SYN_RCVD:
                str = "SYN_RCVD";
                break;
            default:
                sprintf(str, "%hhu", state);
        }
    }

 
    ////////////////////////////////// connect /////////////////////////////////
    // Establishes a connection to the specified destination and port
    socket_t connect(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        uint16_t size = call ServerList.size();
        uint16_t i;

        for (i = 0; i < size; i++) {
            socket_store_t socket = call ServerList.get(i);

            if (socket.src == srcPort) {
                    // Make copy of the server socket for the connection
                    socket_store_t new_socket = socket;
                    new_socket.state = LISTEN;
                    new_socket.dest.addr = dest;
                    new_socket.dest.port = destPort;
                    memset(new_socket.rcvdBuff, 255, SOCKET_BUFFER_SIZE);
                    return addSocket(new_socket);
            }
        }
        // No server socket found
        return 0;
    }

    ////////////////////////////////// addSocket /////////////////////////////////
    // Adds a new socket to the SocketMap and assigns a file descriptor  
    socket_t addSocket(socket_store_t socket) {
        socket_t fd = next_fd;
        //insert socket into map
        call SocketMap.insert(next_fd, socket); 
        //get next available file discripter
        next_fd = getNextFD();
        return fd;
    }

    ////////////////////////////////// updateState /////////////////////////////////
    // Updates the state of an existing socket
    void updateState(socket_t socketFD, enum socket_state new_state) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] updateState: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        socket.state = new_state;
        call SocketMap.insert(socketFD, socket);
    }

     ////////////////////////////////// update Socket /////////////////////////////////
    // Updates socket, technically creating a new socket
    void updateSocket(socket_t socketFD, socket_store_t new_socket) {
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] updateSocket: Invalid socket descriptor\n");
            return;
        }
        
        call SocketMap.insert(socketFD, new_socket);
    }

    ////////////////////////////////// TCP ACK /////////////////////////////////
    // create an ACK 
    bool isAcked(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isAcked: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (seq == 65535) { // SYN/FIN packets (special case in this implementation)
            return socket.state == SYN_RCVD
                || socket.state == ESTABLISHED
                || socket.state == CLOSED;
        }

        if (socket.lastAck < socket.lastSent) { 
            return seq > socket.lastSent || seq <= socket.lastAck;
        }
        else { 
            return seq > socket.lastSent && seq <= socket.lastAck;
        }
    }

////////////////////// Read Sequ. number /////////////////////////
// Function to check if a sequence number has been read

    bool isRead(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isRead: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (socket.lastRcvd < socket.lastRead) { 
            return seq >= socket.lastRead || seq < socket.lastRcvd;
        }
        else { 
            return seq >= socket.lastRead && seq < socket.lastRcvd;
        }
    }

////////////////////// Check sequ.written////////////////////////////
// Function to check if a sequence number has been written

    bool isWritten(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;
    // Check if the socket file descriptor is valid
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isWritten: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (socket.lastAck < socket.lastWritten) { // Normal Case
            return seq >= socket.lastWritten || seq < socket.lastAck;
        }
        else { // Wraparound
            return seq >= socket.lastWritten && seq < socket.lastAck;
        }
    }

///////////////////////////// write to socket ///////////////////////
// Function to write a message to a socket

    void write(socket_t socketFD, pack* msg) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] write: Invalid file descriptor\n");
            return;
        }
        
        call CurrentMessages.pushfrontdrop(*msg);
        sendNextFromSocket(socketFD);             
    }

  ///////////////////////// Full socket with data ////////////////////
  // Function to fill the socket's send buffer with data

    uint8_t fill(socket_store_t* socket, uint32_t transfer) {
        uint32_t i;
        uint8_t count;

        // Reset lastWritten if it exceeds the buffer size
        if (socket->lastWritten >= SOCKET_BUFFER_SIZE) {
            socket->lastWritten = 0;
        }

        if (transfer == 0) {
            if(socket->flag == 0) {
                return 0;
            }
             // Calculate transfer amount and initial count based on the send buffer and flag
            transfer = socket->sendBuff[socket->lastWritten] + socket->flag;
            count = socket->sendBuff[socket->lastWritten];
        } else {
            socket->flag = transfer;
            count = 0;
        }

        for (i = 0; i < socket->flag; i++) {
            uint8_t offset = socket->lastWritten+1;

            if (offset == SOCKET_BUFFER_SIZE) {
                offset = 0;
            }

             // Check if the next position in the buffer is available
            if (socket->lastWritten + 1 < SOCKET_BUFFER_SIZE) {
                if (socket->lastWritten + 1 != socket->lastSent) {
                    socket->sendBuff[offset] = count;
                    socket->lastWritten++;
                    count++;
                }
                else {
                    socket->flag -= count;
                    return socket->flag;
                }
            }
            else if (0 != socket->lastSent) {
                socket->sendBuff[offset] = count;
                socket->lastWritten++;
                count++;
            }
            else {
                socket->flag -= count;
                return socket->flag;
            }
        }

       

        return 0;
    }

   
    void printUnread(socket_t socketFD) {
        socket_store_t socket;
        uint16_t i;
        uint16_t count = 0;
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] printPayload: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        if (!socketFD) {

        for (i = socket.lastRead+1; socket.lastRcvd; i++) {
            if (i >= SOCKET_BUFFER_SIZE) {
                i = 0;
            }
            if (count > SOCKET_BUFFER_SIZE) {
                break;
            }
            dbg(GENERAL_CHANNEL, "%d, \n", socket.rcvdBuff[i]);
            socket.lastRead = i;
            count++;
        }
        }
        updateSocket(socketFD, socket);
    }


    void sendNextFromSocket(socket_t socketFD) {
        pack packet;
        tcp_header header;
        socket_store_t socket;
        uint16_t i;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendNextFromSocket: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        packet = call CurrentMessages.front();
        memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);

        signal TCP.route(&packet);
        call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
    }

    ////////////////////////////////// sendNextData /////////////////////////////////
    // Prepares the next data packet for transmission   
    void sendNextData(socket_t socketFD) {
        pack packet;
        tcp_header header;
        socket_store_t socket;
        uint16_t i;


        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendNextFromSocket: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        
        if (socket.lastWritten == socket.lastSent) {
            return;
        }

        if (socket.lastSent == SOCKET_BUFFER_SIZE) {
            socket.lastSent = 1;
        }

        if (socket.lastSent + TCP_PAYLOAD_SIZE >= SOCKET_BUFFER_SIZE) {
            uint32_t extra = TCP_PAYLOAD_SIZE + socket.lastSent - SOCKET_BUFFER_SIZE;
            for (i = 0; i < TCP_PAYLOAD_SIZE - extra; i++) {
                temp_buffer[i] = socket.sendBuff[socket.lastSent+i];
            }
            for (i = 0; i < extra; i++) {
                temp_buffer[extra+i] = socket.sendBuff[i];
            }
        } else {
            for (i = 0; i < TCP_PAYLOAD_SIZE; i++) {
                temp_buffer[i] = socket.sendBuff[socket.lastSent+i];
            }
        }

   
        //sendDat(socketFD, myData, TCP_PAYLOAD_SIZE);
        sendDat(socketFD, temp_buffer, TCP_PAYLOAD_SIZE);
        call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
    }


////////////////////////////////// remove Ack  /////////////////////////////////
// Function to remove an acknowledged packet from the current messages list
    void removeAck(tcp_header ack_header) {
        uint16_t i;
        uint16_t size = call CurrentMessages.size();

    // Loop through the current messages to find the matching ACK
        for (i = 0; i < size; i++) {
            pack tempPack = call CurrentMessages.get(i);
            tcp_header tempHeader;
            memcpy(&tempHeader, &tempPack.payload, PACKET_MAX_PAYLOAD_SIZE);

            // Check if the sequence number and destination port match the ACK header
            if (tempHeader.seq == ack_header.seq &&
                tempHeader.dest_port == ack_header.src_port) {
                    call CurrentMessages.remove(i);
                    return;
            }
        }
    }
    
///////////////////// create tcp server ////////////////////////
// Command to start a TCP server on a specified port

    command void TCP.startServer(uint16_t port) {
        uint16_t num_connections = call SocketMap.size();
        socket_store_t socket;

        // Check if the maximum number of sockets has been reached
        if (num_connections == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "[Error] startServer: Cannot create server at Port %hhu: Max num of sockets reached\n", port);
        }

        // Initialize the socket with the specified port and default values
        socket.src = port;
        socket.state = LISTEN;
        socket.dest.addr = ROOT_SOCKET_ADDR;
        socket.dest.port = ROOT_SOCKET_PORT;
        socket.lastWritten = SOCKET_BUFFER_SIZE;
        socket.lastAck = SOCKET_BUFFER_SIZE;
        socket.lastSent = SOCKET_BUFFER_SIZE;
        socket.lastRcvd = SOCKET_BUFFER_SIZE;
        socket.effectiveWindow = 1;
        socket.flag = 0;
        socket.RTT = default_rtt;
        // Add the socket to the server list
        call ServerList.pushbackdrop(socket);
        dbg(TRANSPORT_CHANNEL, "Server started, it is waiting for connction on Port %hhu\n", port);
    }

 
 // Command to start a TCP client to connect to a specified destination and port
    command void TCP.startClient(uint16_t dest, uint16_t srcPort,
                                        uint16_t destPort, uint16_t transfer) {
        socket_store_t socket;
        socket_t socketFD;
        uint16_t i;

        // Initialize the socket with the specified source and destination details
        socket.src = srcPort;
        socket.dest.port = destPort;
        socket.dest.addr = dest;
        socket.state = SYN_SENT;
        socket.lastWritten = SOCKET_BUFFER_SIZE;
        socket.lastAck = SOCKET_BUFFER_SIZE;
        socket.lastSent = SOCKET_BUFFER_SIZE;
        socket.lastRcvd = SOCKET_BUFFER_SIZE;
        socket.effectiveWindow = 1;
        socket.RTT = default_rtt;
        socket.flag = 0;
        socket.nextExpected = 0;
        memset(socket.sendBuff, '\0', SOCKET_BUFFER_SIZE);

        // Fill the socket's send buffer with the transfer data
        fill(&socket, transfer);
        socketFD = addSocket(socket);

        updateSocket(socketFD, socket);
        sendSyn(socketFD);

        dbg(TRANSPORT_CHANNEL, "Client started on Port source %hhu with destination node of %hu: and destination port of %hhu\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %hu bytes to destination...\n", transfer);
    }

///////////////////// shutdown clinet side ////////////////////////
// Function to close TCP client  
    command void TCP.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        socket_t socketFD = getFD(dest, srcPort, destPort);
        dbg(TRANSPORT_CHANNEL, "Closing client on Port %hhu with destination %hu: %hhu\n", srcPort, dest, destPort);
        
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] closeClient: Invalid file descriptor\n");
        }

        sendFin(socketFD);
        updateState(socketFD, CLOSED);
    }

////////////////////// THE MOST IMPORTANT FUNCTION IN THE CODE////////////////////
///////////// Process received messages/////////////////
// Once establish connection, this function will process recevied packets
command void TCP.receive(pack* msg) {
    socket_t socketFD;
    socket_store_t socket;
    tcp_header header;
    char dbg_string[20];
    uint16_t i;
    uint16_t x;

    // Copy the TCP header from the packet payload
    memcpy(&header, &(msg->payload), PACKET_MAX_PAYLOAD_SIZE);

    // If SYN flag is set, attempt connection
    if (header.flag == SYN) {
        connect(msg->src, header.dest_port, header.src_port);
    }

    // Retrieve socket file descriptor based on message source and destination ports
    socketFD = getFD(msg->src, header.dest_port, header.src_port);

    // Check if there’s an associated socket, else log an error and exit
    if (!socketFD) {
        dbg(TRANSPORT_CHANNEL, "[Error] receive: No socket associated with message from Node %hu\n", msg->src);
        return;
    }

    // Retrieve socket information
    socket = call SocketMap.get(socketFD);

    // Log packet details and socket information
    dbg(TRANSPORT_CHANNEL, "================== TCP Packet received ===============\n");
   // logPack(msg);
   // logHeader(&header);
    dbg(TRANSPORT_CHANNEL, "****************** Socket ********************\n");
   // logSocket(&socket);
    dbg(TRANSPORT_CHANNEL, "------------------------------------------\n\n");

    dbg(GENERAL_CHANNEL, "====================================\n");
    dbg(GENERAL_CHANNEL, "|         Connection Status        |\n");
    dbg(GENERAL_CHANNEL, "====================================\n");

    // Handle packet based on socket state
    switch(socket.state) {
        case CLOSED:
            if (header.flag == FIN) {
                sendAck(socketFD, msg);
                call SocketMap.remove(socketFD);
                dbg(GENERAL_CHANNEL, "Connection closed with Node %hu\n", msg->src);
            }
            break;

        case LISTEN:
            if (header.flag == SYN) {  
                sendSyn(socketFD);
                sendAck(socketFD, msg);
                updateState(socketFD, SYN_RCVD);
                dbg(GENERAL_CHANNEL, "Connection established with Node %hu\n", msg->src);
            }
            break;

        case ESTABLISHED:
            if (header.flag == DAT) {
                if (isAcked(socketFD, header.seq)) {
                    break;
                }
                sendAck(socketFD, msg);

                // Process received data and update buffer
                if (socket.lastRcvd >= SOCKET_BUFFER_SIZE) {
                    for (i = 0; i < header.payload_size; i++) {
                        socket.rcvdBuff[i] = header.payload[i];
                    }
                    socket.lastRcvd = header.payload_size;
                } else if (socket.lastRcvd + header.payload_size >= SOCKET_BUFFER_SIZE) {
                    uint16_t extra = socket.lastRcvd + header.payload_size - SOCKET_BUFFER_SIZE;
                    for (i = 0; i < header.payload_size - extra; i++) {
                        socket.rcvdBuff[socket.lastRcvd + i] = header.payload[i];
                    }
                    for (i = 0; i < extra; i++) {
                        socket.rcvdBuff[i] = header.payload[header.payload_size - extra - i];
                    }
                    socket.lastRcvd = extra;
                } else {
                    for (i = 0; i < header.payload_size; i++) {
                        socket.rcvdBuff[socket.lastRcvd + i] = header.payload[i];
                    }
                    socket.lastRcvd += header.payload_size;
                }

                // Print received data in both hex and decimal format with a descriptive layout
                dbg(GENERAL_CHANNEL, "Received data (Hex | Decimal):\n");
                for (i = 0; i < header.payload_size; i++) {
                    dbg(GENERAL_CHANNEL, "0x%02X | %3u ", header.payload[i], header.payload[i]);
                    if ((i + 1) % 8 == 0) {
                        dbg(GENERAL_CHANNEL, "\n");  // Print 8 bytes per line
                    }
                }
                dbg(GENERAL_CHANNEL, "\n\n"); // Newline for formatting

                updateSocket(socketFD, socket);
                printUnread(socketFD);
            }
            else if (header.flag == ACK) {
                call PacketTimer.stop();
                removeAck(header);
                fill(&socket, 0);
                socket.nextExpected = header.seq + 1;
                updateSocket(socketFD, socket);
                sendNextData(socketFD);
                dbg(GENERAL_CHANNEL, "ACK received from Node %hu; ready to send next data.\n", msg->src);
            }
            else if (header.flag == FIN) {
                sendAck(socketFD, msg);
                sendFin(socketFD);
                updateState(socketFD, CLOSED);
                dbg(GENERAL_CHANNEL, "FIN received; connection closed with Node %hu.\n", msg->src);
            }
            break;

        case SYN_SENT:
            if (header.flag == ACK) {
                updateState(socketFD, ESTABLISHED);
                call PacketTimer.stop();
                removeAck(header);
                sendNextData(socketFD);
                dbg(GENERAL_CHANNEL, "Connection established with Node %hu after ACK.\n", msg->src);
            }
            else if (header.flag == SYN) {
                sendAck(socketFD, msg);
            }
            else if (header.flag == DAT) {
                updateState(socketFD, ESTABLISHED);
                call TCP.receive(msg);
                break;
            }
            else {
                dbg(TRANSPORT_CHANNEL, "[Error] receive: Invalid packet type for SYN_SENT state\n");
            }
            break;

        case SYN_RCVD:
            if (header.flag == ACK) {   
                updateState(socketFD, ESTABLISHED);
                call PacketTimer.stop();
                removeAck(header);
                dbg(GENERAL_CHANNEL, "Connection moved to ESTABLISHED state after ACK from Node %hu.\n", msg->src);
            }
            else if (header.flag == DAT) {
                updateState(socketFD, ESTABLISHED);
                call TCP.receive(msg);
                break;
            }
            else {
                dbg(TRANSPORT_CHANNEL, "[Error] receive: Invalid packet type for SYN_RCVD state\n");
            }
            break;

        default:
            getState(socket.state, dbg_string);
            dbg(TRANSPORT_CHANNEL, "[Error] receive: Invalid socket state %s\n", dbg_string);
            dbg(GENERAL_CHANNEL, "Invalid socket state encountered. Check state machine for issues.\n");
    }
}

  


   /////////////////////  Paker timer  ////////////////////////
   // Event handler for when the PacketTimer fires, indicating a packet timeout
    event void PacketTimer.fired(){
        pack packet;
        tcp_header header;
        socket_store_t socket;
        socket_t socketFD;

        // Check if the message queue is empty; if not empty, exit as no retransmission is needed
        if (!call CurrentMessages.isEmpty()) {
            return;
        }

       // Retrieve the first packet from the message queue for retransmission
        packet = call CurrentMessages.front();
        memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);

        socketFD = getFD(packet.dest, header.src_port, header.dest_port);

         // If no valid socket file descriptor, log an error and exit
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] PacketTimer.fired: Invalid file descriptor\n");
            return;
        }

        dbg(TRANSPORT_CHANNEL, "Packet timed out... retransmitting\n");

        socket = call SocketMap.get(socketFD);

        while(isAcked(socketFD, header.seq)) {
            call CurrentMessages.remove(0);
            if (call CurrentMessages.isEmpty()) {
                return;
            }
            packet = call CurrentMessages.front();
            
            memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);
            socketFD = getFD(packet.dest, header.src_port, header.dest_port);

            if (!socketFD) {
                dbg(TRANSPORT_CHANNEL, "[Error] PacketTimer.fired: Invalid file descriptor\n");
                return;
            }  

            socket = call SocketMap.get(socketFD);          
        }

        // If there are still unacknowledged packets in the queue, retransmit the packet and restart the timer
        if (!call CurrentMessages.isEmpty()) {
            signal TCP.route(&packet);
            call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
        }
    }

   ///////////////////// SYN packet  ////////////////////////
   // Function to send a SYN packet to initiate a TCP connection
    void sendSyn(socket_t socketFD) {
        socket_store_t socket;
        pack synPack;
        tcp_header syn_header;
        // Check if the socket file descriptor is valid; if not, log an error and exit                
        if (!socketFD) {
            dbg (TRANSPORT_CHANNEL, "[Error] sendSyn: Invalid file descriptor\n");
            return;
        }

         // Retrieve socket information from the socket map using the file descriptor
        socket = call SocketMap.get(socketFD);

        synPack.src = TOS_NODE_ID;
        synPack.dest = socket.dest.addr;
        synPack.seq = signal TCP.getSequence();
        synPack.TTL = MAX_TTL;
        synPack.protocol = PROTOCOL_TCP;

        // Configure the TCP header fields for the SYN packet
        syn_header.src_port = socket.src;
        syn_header.dest_port = socket.dest.port;
        syn_header.flag = SYN;
        syn_header.seq = 65535;
        syn_header.advert_window = socket.effectiveWindow;

        memcpy(&synPack.payload, &syn_header, TCP_PAYLOAD_SIZE);

        write(socketFD, &synPack);
    }

   /////////////////////  ACK function   ////////////////////////
   // Function to send an ACK packet in response to a received message
    void sendAck(socket_t socketFD, pack* original_message) {
        socket_store_t socket;
        tcp_header originalHeader;
        pack ackPack;
        tcp_header ackHeader;

        // Check if the socket file descriptor is valid; if not, log an error and exit
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendAck: Invalid file descriptor\n");
            return;
        }

         // Retrieve socket information from the socket map using the file descriptor
        socket = call SocketMap.get(socketFD);
        memcpy(&originalHeader, &(original_message->payload), PACKET_MAX_PAYLOAD_SIZE);

        ackPack.src = TOS_NODE_ID;
        ackPack.dest = socket.dest.addr;
        ackPack.seq = signal TCP.getSequence();
        ackPack.TTL = MAX_TTL;
        ackPack.protocol = PROTOCOL_TCP;
        // Configure the TCP header fields for the ACK packet
        ackHeader.src_port = socket.src;
        ackHeader.dest_port = socket.dest.port;
        ackHeader.seq = originalHeader.seq; 
        ackHeader.advert_window = socket.effectiveWindow;
        ackHeader.flag = ACK;
        ackHeader.payload_size = 0;
        memset(&ackHeader.payload, '\0', TCP_PAYLOAD_SIZE);

        memcpy(&ackPack.payload, &ackHeader, PACKET_MAX_PAYLOAD_SIZE);
        
        signal TCP.route(&ackPack);
    }            

    /////////////////////  finish Function  ////////////////////////
   //Send finish once everything is done
    void sendFin(socket_t socketFD) {
        socket_store_t socket; 
        pack finPack;
        tcp_header fin_header;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendFin: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        finPack.src = TOS_NODE_ID;
        finPack.dest = socket.dest.addr;
        finPack.seq = signal TCP.getSequence();
        finPack.TTL = MAX_TTL;
        finPack.protocol = PROTOCOL_TCP;

        fin_header.src_port = socket.src;
        fin_header.dest_port = socket.dest.port;
        fin_header.seq = 65535;
        fin_header.advert_window = socket.effectiveWindow;
        fin_header.flag = FIN;

        memcpy(&finPack.payload, &fin_header, PACKET_MAX_PAYLOAD_SIZE);
                                                                                                       
        write(socketFD, &finPack);                
    }

   ///////////////////// Sending data  ////////////////////////
   // Function to send data on TCP connection
    void sendDat(socket_t socketFD, uint8_t* data, uint16_t size) {
        socket_store_t socket;
        pack datPack;
        tcp_header dat_header;
        uint16_t i;
                        
        if (!socketFD) {
            dbg (TRANSPORT_CHANNEL, "[Error] sendDat: Invalid file descriptor\n");
            return;
        }
         // Retrieve socket information from the socket map using the file descriptor
        socket = call SocketMap.get(socketFD);

        datPack.src = TOS_NODE_ID;
        datPack.dest = socket.dest.addr;
        datPack.seq = signal TCP.getSequence();
        datPack.TTL = MAX_TTL;
        datPack.protocol = PROTOCOL_TCP;

        dat_header.src_port = socket.src;
        dat_header.dest_port = socket.dest.port;
        dat_header.flag = DAT;
        dat_header.seq = socket.nextExpected;
        dat_header.advert_window = socket.effectiveWindow;
        dat_header.payload_size = size;

        for (i = 0; i < size; i++) {
            dat_header.payload[i] = temp_buffer[i];
        }
        // Copy the configured FIN header into the packet payload
        memcpy(&datPack.payload, &dat_header, TCP_PAYLOAD_SIZE);
        write(socketFD, &datPack);
       
    } 
/////////////////////// functio nto change the data send /////////////////////
// we can send custom data using the following function
   void sendCustomData(socket_t socketFD) {
    // Define custom data payload
    uint8_t myData[] = "This is the data I want to send over TCP!";
    uint16_t dataSize = sizeof(myData) - 1;  // Exclude null terminator

    // Call sendDat with custom data
    if (socketFD) {
        sendDat(socketFD, myData, dataSize);
    } else {
        printf("Invalid socket descriptor.\n");
    }
}


}