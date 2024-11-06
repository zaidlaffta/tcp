#ifndef TCP_HEADER_H
#define TCP_HEADER_H

#include <stdio.h>

enum {
    TCP_HEADER_SIZE = 8,
    TCP_PAYLOAD_SIZE = 20 - TCP_HEADER_SIZE,
};

enum flags {
    SYN,
    ACK,
    FIN,
    DAT,
};

typedef nx_struct tcp_header {
    nx_uint8_t src_port;
    nx_uint8_t dest_port;
    nx_uint16_t seq;
    nx_uint16_t advert_window;
    nx_uint8_t flag;
    nx_uint8_t payload_size; // in bytes
    nx_uint8_t payload[TCP_PAYLOAD_SIZE];
} tcp_header;

void logHeader(tcp_header* header) {
    char* flag = "";
    uint16_t i;
    switch (header->flag) {
        case SYN:
            flag = "SYN";
            break;
        case ACK:
            flag = "ACK";
            break;
        case FIN:
            flag = "FIN";
            break;
        case DAT:
            flag = "DAT";
            break;
        default:
            flag = "UNKNOWN";
    }
    dbg(TRANSPORT_CHANNEL, "src_port: %hhu, dest_port: %hhu, seq: %hu, advert_window: %hu, flag: %s, payload_size: %hhu, payload: ",
        header->src_port, header->dest_port, header->seq, header->advert_window, flag, header->payload_size);
    
    for (i = 0; i < header->payload_size; i++) {
        printf("%d, ", header->payload[i]);
    }
    printf("\n");

}

#endif // TCP_HEADER_H
