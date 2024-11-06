/**
 * @author Jadon Hansell
 * 
 * Distance vector implementtion for routing packets
 */

#include <Timer.h>
#include "../../includes/route.h"

configuration RoutingC {
    provides interface Routing;
}

implementation {
    components RoutingP;
    Routing = RoutingP;

    components RandomC;
    RoutingP.Random -> RandomC;

    // No more than 256 nodes in system 
    components new ListC(Route, 256);
    RoutingP.RoutingTable -> ListC;

    components new SimpleSendC(AM_PACK);
    RoutingP.Sender -> SimpleSendC;

    components new TimerMilliC() as TriggeredEventTimer;
    RoutingP.TriggeredEventTimer -> TriggeredEventTimer;

    components new TimerMilliC() as RegularTimer;
    RoutingP.RegularTimer -> RegularTimer;
}