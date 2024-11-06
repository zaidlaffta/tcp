/**
 * @author Jadon Hansell
 * 
 * Flooding method for packet transmission
 */

#include "../../includes/packet_id.h"

configuration FloodingHandlerC {
    provides interface FloodingHandler;
}

implementation {
    components FloodingHandlerP;
    FloodingHandler = FloodingHandlerP;

    components new SimpleSendC(AM_PACK);
    FloodingHandlerP.Sender -> SimpleSendC;

    components new ListC(packID, 64);
    FloodingHandlerP.PreviousPackets -> ListC;
}
