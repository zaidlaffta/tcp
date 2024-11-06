/**
 * @author Jadon Hansell
 * 
 * Flooding method for packet transmission
 */

#include "../../includes/packet_id.h"

configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components FloodingP;
    Flooding = FloodingP;

    components new SimpleSendC(AM_PACK);
    FloodingP.Sender -> SimpleSendC;

    components new ListC(packID, 64);
    FloodingP.PreviousPackets -> ListC;
}
