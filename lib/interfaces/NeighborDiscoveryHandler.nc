#include "../../includes/packet.h"

interface NeighborDiscoveryHandler {
    command void discover();
    command void recieve(pack* msg);
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command void printNeighbors();
    event uint16_t getSequence();
}
