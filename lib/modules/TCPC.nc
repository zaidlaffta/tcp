#include <Timer.h>
#include "../../includes/socket.h"

configuration TCPC{
    provides interface TCP;
}

implementation {
    // Declare TCPP componetns
    components TCPP;
    TCP = TCPP;
    
    components new TimerMilliC();
    TCPP.PacketTimer -> TimerMilliC;
    // Instantiate a hashmap with entries for each socket
    components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS);
    TCPP.SocketMap -> HashmapC;

    components new ListC(socket_store_t, MAX_NUM_OF_SOCKETS) as ServerListC;
    TCPP.ServerList -> ServerListC;
    // Connect TCPP's CurrentMessages interface to the message list
    components new ListC(pack, (SOCKET_BUFFER_SIZE / PACKET_SIZE) * 10) as CurrentMessagesC;
    TCPP.CurrentMessages -> CurrentMessagesC;


}

