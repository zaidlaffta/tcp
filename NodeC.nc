

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components RandomC;
    Node.Random -> RandomC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components FloodingC;
    Node.Flooding -> FloodingC;

    components new TimerMilliC() as NeighborTimer;
    Node.NeighborTimer -> NeighborTimer;

    components new TimerMilliC() as RoutingTimer;
    Node.RoutingTimer -> RoutingTimer;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    components RoutingC;
    Node.Routing -> RoutingC;

    components TCPC;
    Node.TCP -> TCPC;
}
