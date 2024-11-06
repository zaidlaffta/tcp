#include "../../includes/packet.h"
#include "../../includes/packet_id.h"

module FloodingP {
    provides interface Flooding;

    uses interface SimpleSend as Sender;
    uses interface List<packID> as PreviousPackets;
}

implementation {

    bool isDuplicate(uint16_t src, uint16_t seq) {
        uint16_t i;
        // Loop over previous packets
        for (i = 0; i < call PreviousPackets.size(); i++) {
            packID prevPack = call PreviousPackets.get(i);

            // Packet can be identified by src && seq number
            if (prevPack.src == src && prevPack.seq == seq) {
                return TRUE;
            }
        }
        return FALSE;
    }

    bool isValid(pack* msg) {

        if (isDuplicate(msg->src, msg->seq)) {
            dbg(FLOODING_CHANNEL, "Duplicate packet. Dropping...\n");
            return FALSE;
        }

        return TRUE;
    }

    void sendFlood(pack* msg) {
        if (msg->dest != AM_BROADCAST_ADDR && msg->src != TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL, "Packet recieved from %d. Destination: %d. Flooding...\n", msg->src, msg->dest);
        } 

        call Sender.send(*msg, AM_BROADCAST_ADDR);
    }

    command void Flooding.flood(pack* msg) {
        if (isValid(msg)) {
            packID packetID;
            packetID.src = msg->src;
            packetID.seq = msg->seq;
            
            call PreviousPackets.pushbackdrop(packetID);

            sendFlood(msg);
        }
    }
}
