#include <Timer.h>
#include "../../includes/socket.h"

configuration TCPHandlerC{
    provides interface TCPHandler;
}

implementation {
    components TCPHandlerP;
    TCPHandler = TCPHandlerP;
    
    components new TimerMilliC();
    TCPHandlerP.PacketTimer -> TimerMilliC;
    
    components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS);
    TCPHandlerP.SocketMap -> HashmapC;

    components new ListC(socket_store_t, MAX_NUM_OF_SOCKETS) as ServerListC;
    TCPHandlerP.ServerList -> ServerListC;

    components new ListC(pack, (SOCKET_BUFFER_SIZE / PACKET_SIZE) * 10) as CurrentMessagesC;
    TCPHandlerP.CurrentMessages -> CurrentMessagesC;


}

