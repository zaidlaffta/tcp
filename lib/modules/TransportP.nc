#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"

module TransportP {
    provides interface Transport;

    uses interface Timer<TMilli> as SrcTimeout;
    uses interface Hashmap<socket_store_t> as SocketMap;
}

implementation {

    /**
     * Get a socket if there is one available.
     * @Side Client/Server
     * @return
     *    socket_t - return a socket file descriptor which is a number
     *    associated with a socket. If you are unable to allocate
     *    a socket then return a NULL socket_t.
     */
    command socket_t socket() {
        uint32_t* fds = call SocketMap.getKeys(); 
        uint16_t size = call SocketMap.size();
        socket_t fd;
        uint8_t i;

        if (size == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "[Error] socket: No room for new socket\n");
            return NULL;
        }

        // Find a socket file descriptor greater than 0 that's unused
        for (fd = 1; fd > 0; fd++) {
            bool found = FALSE;
            for (i = 0; i < size; i++) {
                if (fd != (socket_t)fds[i]) {
                    found = TRUE;
                }
            }

            // Free socket file descriptor found
            if (!found) {
                socket_store_t socket;

                socket.flag = FALSE; // Uninstantiated socket
                socket.state = CLOSED:
                socket.src = TOS_NODE_ID;
                socket.dest.port = ROOT_SOCKET_PORT; // REVIEW: Possibly incorrect
                socket.dest.addr = ROOT_SOCKET_ADDR; // REVIEW: Possible incorrect
                socket.lastWritten = 0;
                socket.lastAck = 0;
                socket.lastSent = 0;
                socket.lastRead = 0;
                socket.leastRcvd = 0;
                socket.nextExpected = 0;
                socket.RTT = 0;
                socket.effectiveWindow = 0;
                memset(&socket.sendBuff, '\0', SOCKET_BUFFER_SIZE);
                memset(&socket.rcvdBuff, '\0', SOCKET_BUFFER_SIZE);

                call SocketMap.insert(fd, socket);
                return fd;
            }      
        }

        dbg(TRANSPORT_CHANNEL, "[Error] socket: No valid next file descriptor found\n");
        return NULL;
    }

    /**
     * Bind a socket with an address.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       you are binding.
     * @param
     *    socket_addr_t *addr: the source port and source address that
     *       you are biding to the socket, fd.
     * @Side Client/Server
     * @return error_t - SUCCESS if you were able to bind this socket, FAIL
     *       if you were unable to bind.
     */
    command error_t bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t socket = call SocketMap.get(fd);

        if (!fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] bind: Invalid file descriptor\n");
            return FAIL;
        }

        socket.src = addr->port;
        call SocketMap.insert(fd, socket);
        return SUCCESS;
    }

    /**
     * Checks to see if there are socket connections to connect to and
     * if there is one, connect to it.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that is attempting an accept. remember, only do on listen. 
     * @side Server
     * @return socket_t - returns a new socket if the connection is
     *    accepted. this socket is a copy of the server socket but with
     *    a destination associated with the destination address and port.
     *    if not return a null socket.
     */
    command socket_t accept(socket_t fd) {
        socket_store_t socket;
        socket_t new_fd = call Transport.socket();

        if (!fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] accept: Invalid server file descriptor\n");
            return NULL;
        }

        socket = call SocketMap.get(fd);

        if (socket.flag) {
            dbg(TRANSPORT_CHANNEL, "[Error] accept: Root socket in use\n");
            return NULL;
        }

        if (!new_fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] accept: Invalid new file descriptor\n");
            return NULL;
        }

        socket.flag == TRUE;
        socket.dest.addr = 0; // FIXME: How do we get the addr and port?
        socket.dest.port = 0;
        call SocketMap.insert(new_fd, socket);
        return new_fd;
    }

    /**
     * Write to the socket from a buffer. This data will eventually be
     * transmitted through your TCP implimentation.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that is attempting a write.
     * @param
     *    uint8_t *buff: the buffer data that you are going to wrte from.
     * @param
     *    uint16_t bufflen: The amount of data that you are trying to
     *       submit.
     * @Side For your project, only client side. This could be both though.
     * @return uint16_t - return the amount of data you are able to write
     *    from the pass buffer. This may be shorter then bufflen
     */
    command uint16_t write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t socket;

        if (!fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] write: Invalid file descriptor\n");
            return NULL;
        }

        socket = call SocketMap.get(fd);
        uint8_t start = socket.lastWritten+1;

        // REVIEW: May be one off
        // Can fit entire buffer into socket
        if (bufflen < SOCKET_BUFFER_SIZE - start) {
            memcpy(socket.sendBuff+start, buff, bufflen);
            socket.lastWritten = start + bufflen;
            call SocketMap.insert(fd, socket);
            return bufflen;
        // Can't fit entire buffer into socket, wrap around to beginning
        } else  if(NULL){
            // FIXME: Deal with wraparound using lastAck and lastSent
        // No room in socket, put in what you can
        } else {

        }

        return NULL;
    }

    /**
     * This will pass the packet so you can handle it internally. 
     * @param
     *    pack *package: the TCP packet that you are handling.
     * @Side Client/Server 
     * @return uint16_t - return SUCCESS if you are able to handle this
     *    packet or FAIL if there are errors.
     */
    command error_t receive(pack* package) {
        tcp_header header;
        memcpy(&header, &package->payload, PACKET_MAX_PAYLOAD_SIZE);
    }

    /**
     * Read from the socket and write this data to the buffer. This data
     * is obtained from your TCP implimentation.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that is attempting a read.
     * @param
     *    uint8_t *buff: the buffer that is being written.
     * @param
     *    uint16_t bufflen: the amount of data that can be written to the
     *       buffer.
     * @Side For your project, only server side. This could be both though.
     * @return uint16_t - return the amount of data you are able to read
     *    from the pass buffer. This may be shorter then bufflen
     */
    command uint16_t read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t socket;

        if (!fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] read: Invalid file descriptor\n");
            return NULL;
        }

        socket = call SocketMap.get(fd);

        // FIXME: Copied from write, change from here on
        uint8_t start = socket.lastWritten+1;

        // REVIEW: May be one off
        // Can fit entire buffer into socket
        if (bufflen < SOCKET_BUFFER_SIZE - start) {
            memcpy(socket.sendBuff+start, buff, bufflen);
            socket.lastWritten = start + bufflen;
            call SocketMap.insert(fd, socket);
            return bufflen;
        // Can't fit entire buffer into socket, wrap around to beginning
        } else  if(NULL){
            // FIXME: Deal with wraparound using lastAck and lastSent
        // No room in socket, put in what you can
        } else {

        }

        return NULL;
    }

    /**
     * Attempts a connection to an address.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that you are attempting a connection with. 
     * @param
     *    socket_addr_t *addr: the destination address and port where
     *       you will atempt a connection.
     * @side Client
     * @return socket_t - returns SUCCESS if you are able to attempt
     *    a connection with the fd passed, else return FAIL.
     */
    command error_t connect(socket_t fd, socket_addr_t * addr) {
        socket_store_t socket;
        if (!fd) {
            dbg(TRANSPORT_CHANNEL, "[Error] connect: Invalid file descriptor\n");
            return FAIL;
        }

        socket = SocketMap.get(fd);

        


        dbg(TRANSPORT_CHANNEL, "Error: Connect not implemented\n");
    }

    /**
     * Closes the socket.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that you are closing. 
     * @side Client/Server
     * @return socket_t - returns SUCCESS if you are able to attempt
     *    a closure with the fd passed, else return FAIL.
     */
    command error_t close(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Error: Close not implemented\n");
    }

    /**
     * A hard close, which is not graceful. This portion is optional.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that you are hard closing. 
     * @side Client/Server
     * @return socket_t - returns SUCCESS if you are able to attempt
     *    a closure with the fd passed, else return FAIL.
     */
    command error_t release(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Error: Release not implemented\n");
    }

    /**
     * Listen to the socket and wait for a connection.
     * @param
     *    socket_t fd: file descriptor that is associated with the socket
     *       that you are hard closing. 
     * @side Server
     * @return error_t - returns SUCCESS if you are able change the state 
     *   to listen else FAIL.
     */
    command error_t listen(socket_t fd) {
        dbg(TRANSPORT_CHANNEL, "Error: Listen not implemented\n");
    }
}