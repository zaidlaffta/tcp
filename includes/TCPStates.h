#ifndef TCPStates
#define TCPStates

/**
 * list of states in a TCP connection
 */
enum {
    CLOSED = 0,
    LISTEN = 1,
    SYN_SENT = 2,
    SYN_RECIEVED = 3,
    ESTABLISHED = 4,
    FIN_WAIT_1 = 5,
    CLOSE_WAIT = 6,
    FIN_WAIT_2 = 7,
    LAST_ACK = 8,
    TIME_WAIT = 9
};

#endif //TCPStates
