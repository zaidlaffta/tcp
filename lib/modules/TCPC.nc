#include <Timer.h>               
#include "../../includes/socket.h" 

configuration TCPC {
    provides interface TCP;       
}

implementation {
    components TCPP;              // Declare TCPP as the main component implementing TCP functionalities
    TCP = TCPP;                   // Connect the TCP interface to the TCPP module

    
    components new TimerMilliC(); 
    TCPP.PacketTimer -> TimerMilliC; 

    components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS); // Instantiate a hashmap with entries for each socket
    TCPP.SocketMap -> HashmapC;    // Connect TCPP's SocketMap interface to the hashmap component

    components new ListC(socket_store_t, MAX_NUM_OF_SOCKETS) as ServerListC; // Instantiate a list for server sockets
    TCPP.ServerList -> ServerListC; // Connect TCPP's ServerList interface to the server list

    components new ListC(pack, (SOCKET_BUFFER_SIZE / PACKET_SIZE) * 10) as CurrentMessagesC; // Create a list for message packets
    TCPP.CurrentMessages -> CurrentMessagesC; // Connect TCPP's CurrentMessages interface to the message list
}

