#include "../../includes/socket.h"

configuration ChatClientC{
    provides interface ChatClient;
}
implementation{
    components ChatClientP
    ChatClient = ChatClientP

    components new ListC(socket_store_t, MAX_NUM_OF_SOCKETS) as UsrList;
    ChatClientP.UsrList -> UsrListC;
}