//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


# include "protocol.h"
#include "channels.h"

enum{
	PACKET_SIZE = 28,
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = PACKET_SIZE - PACKET_HEADER_LENGTH,
	MAX_TTL = 15
};


typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	char* protocol = "";
	switch (input->protocol) {
		case PROTOCOL_PING:
			protocol = "PING";
			break;
		case PROTOCOL_PINGREPLY:
			protocol = "PINGREPLY";
			break;
		case PROTOCOL_LINKEDLIST:
			protocol = "LINKEDLIST";
			break;
		case PROTOCOL_NAME:
			protocol = "NAME";
			break;
		case PROTOCOL_TCP:
			protocol = "TCP";
			break;
		case PROTOCOL_DV:
			protocol = "DV";
			break;
		case PROTOCOL_CMD:
			protocol = "CMD";
			break;
		default:
			protocol = "UNKNOWN";
	}

	if (input->protocol == PROTOCOL_TCP) {
		dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %s\n",
			input->src, input->dest, input->seq, input->TTL, protocol);
	} else {
		dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol: %s Payload: %s\n",
			input->src, input->dest, input->seq, input->TTL, protocol, input->payload);
	}
	
}

enum{
	AM_PACK=6
};

#endif
