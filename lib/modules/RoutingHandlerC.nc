/**
 * @author Jadon Hansell
 * 
 * Distance vector implementtion for routing packets
 */

#include <Timer.h>
#include "../../includes/route.h"

configuration RoutingHandlerC {
    provides interface RoutingHandler;
}

implementation {
    components RoutingHandlerP;
    RoutingHandler = RoutingHandlerP;

    components RandomC;
    RoutingHandlerP.Random -> RandomC;

    // No more than 256 nodes in system 
    components new ListC(Route, 256);
    RoutingHandlerP.RoutingTable -> ListC;

    components new SimpleSendC(AM_PACK);
    RoutingHandlerP.Sender -> SimpleSendC;

    components new TimerMilliC() as TriggeredEventTimer;
    RoutingHandlerP.TriggeredEventTimer -> TriggeredEventTimer;

    components new TimerMilliC() as RegularTimer;
    RoutingHandlerP.RegularTimer -> RegularTimer;
}