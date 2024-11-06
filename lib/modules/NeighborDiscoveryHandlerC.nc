/**
 * @author Jadon Hansell
 * 
 * Neighbor discovery through flooding
 */

#include "../../includes/packet.h"

configuration NeighborDiscoveryHandlerC {
    provides interface NeighborDiscoveryHandler;
}

implementation {
    components NeighborDiscoveryHandlerP;
    NeighborDiscoveryHandler = NeighborDiscoveryHandlerP;

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryHandlerP.Sender -> SimpleSendC;

    components new HashmapC(uint16_t, 256) as Neighbors;
    NeighborDiscoveryHandlerP.Neighbors-> Neighbors;
}
