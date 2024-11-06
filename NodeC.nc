/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

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

    components FloodingHandlerC;
    Node.FloodingHandler -> FloodingHandlerC;

    components new TimerMilliC() as NeighborTimer;
    Node.NeighborTimer -> NeighborTimer;

    components new TimerMilliC() as RoutingTimer;
    Node.RoutingTimer -> RoutingTimer;

    components NeighborDiscoveryHandlerC;
    Node.NeighborDiscoveryHandler -> NeighborDiscoveryHandlerC;

    components RoutingHandlerC;
    Node.RoutingHandler -> RoutingHandlerC;

    components TCPHandlerC;
    Node.TCPHandler -> TCPHandlerC;
}
