

#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node {
    uses interface Boot;
    uses interface SplitControl as AMControl;     // Controls the radio start/stop
    uses interface Receive;                       // Handles incoming messages
    uses interface SimpleSend as Sender;          // Sends simple messages
    uses interface Random;                        // Generates random numbers
    uses interface CommandHandler;                // Handles simulation commands
    uses interface Flooding;                      // Implements flooding protocol
    uses interface Timer<TMilli> as NeighborTimer; // Timer for periodic neighbor discovery
    uses interface NeighborDiscovery;             // Manages neighbor discovery
    uses interface Timer<TMilli> as RoutingTimer; // Timer for periodic routing updates
    uses interface Routing;                       // Manages routing tasks
    uses interface TCP;                           // Implements TCP-like behavior
}

implementation {
    pack sendPackage;                  // Reusable packet struct to prepare outgoing messages
    uint16_t current_seq = 1;          // Packet sequence counter


    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void pingHandler(pack* msg);       // Processes received ping messages
    uint32_t randNum(uint32_t min, uint32_t max);  // Generates random number within a range
    uint16_t getSequence();            // Returns and increments the sequence number

    ////////////////////////////////// Boot.booted /////////////////////////////////
    // Initializes the node at boot by starting radio control and timers
    event void Boot.booted() {
        call AMControl.start();                           // Start the radio
        call NeighborTimer.startPeriodic(randNum(10000, 20000)); // Start neighbor discovery timer with random interval
        call RoutingTimer.startPeriodic(randNum(25000, 35000));  // Start routing timer with random interval
        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    ////////////////////////////////// AMControl.startDone /////////////////////////////////
    // Called when the radio starts successfully. Retries if there's an error.
    event void AMControl.startDone(error_t err) {
        if (err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            call AMControl.start(); // Retry until successful
        }
    }

    event void AMControl.stopDone(error_t err) {}

    ////////////////////////////////// pingHandler /////////////////////////////////
    // Processes incoming ping or ping reply messages and responds as needed
    void pingHandler(pack* msg) {
        switch (msg->protocol) {
            case PROTOCOL_PING:
                dbg(GENERAL_CHANNEL, "--- Ping received from %d\n", msg->src);
                dbg(GENERAL_CHANNEL, "--- Packet Payload: %s\n", msg->payload);
                dbg(GENERAL_CHANNEL, "--- Sending Reply...\n");

                // Prepare and send a ping reply
                makePack(&sendPackage, msg->dest, msg->src, MAX_TTL, PROTOCOL_PINGREPLY, current_seq++, (uint8_t*)msg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call Routing.send(&sendPackage);
                break;
                
            case PROTOCOL_PINGREPLY:
                dbg(GENERAL_CHANNEL, "--- Ping reply received from %d\n", msg->src);
                break;
                
            default:
                dbg(GENERAL_CHANNEL, "Unrecognized ping protocol: %d\n", msg->protocol);
        }
    }

    ////////////////////////////////// Receive.receive /////////////////////////////////
    // Receives incoming messages, processes them based on protocol type and destination
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* myMsg = (pack*) payload;

            // Decrement TTL and discard if expired
            if (myMsg->TTL-- == 0) {
                return msg;
            }

            // Route message to the appropriate protocol handler
            if (myMsg->protocol == PROTOCOL_DV) {
                call Routing.recieve(myMsg);
            } else if (myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID) {
               // call TCP.recieve(myMsg);
               call TCP.receive(myMsg);
            } else if (myMsg->dest == TOS_NODE_ID) {
                pingHandler(myMsg); // Handle as ping
            } else if (myMsg->dest == AM_BROADCAST_ADDR) {
                call NeighborDiscovery.recieve(myMsg); // Handle as neighbor discovery
            } else {
                call Routing.send(myMsg); // Forward to other nodes
            }
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    ////////////////////////////////// NeighborTimer.fired /////////////////////////////////
    // Called periodically to trigger neighbor discovery
    event void NeighborTimer.fired() {
        call NeighborDiscovery.discover();
    }

    ////////////////////////////////// RoutingTimer.fired /////////////////////////////////
    // Updates the routing table with current neighbors periodically
    event void RoutingTimer.fired() {
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t numNeighbors = call NeighborDiscovery.numNeighbors();

        call Routing.updateNeighbors(neighbors, numNeighbors);
        call Routing.start();
    }

    ////////////////////////////////// TCP.route /////////////////////////////////
    // Routes TCP packets through the routing protocol
    event void TCP.route(pack* msg) {
        call Routing.send(msg);
    }

    // Sequence retrieval for various interfaces
    event uint16_t NeighborDiscovery.getSequence() { return getSequence(); }
    event uint16_t Routing.getSequence() { return getSequence(); }
    event uint16_t TCP.getSequence() { return getSequence(); }

    ////////////////////////////////// CommandHandler.ping /////////////////////////////////
    // Prepares and sends a ping message to the specified destination
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Routing.send(&sendPackage);
    }

    ////////////////////////////////// CommandHandler.printNeighbors /////////////////////////////////
    // Outputs a list of the node's discovered neighbors
    event void CommandHandler.printNeighbors() {
        call NeighborDiscovery.printNeighbors();
    }

    ////////////////////////////////// CommandHandler.printRouteTable /////////////////////////////////
    // Outputs the routing table maintained by the node
    event void CommandHandler.printRouteTable() {
        call Routing.printRoutingTable();
    }

    event void CommandHandler.printLinkState() { dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    ////////////////////////////////// CommandHandler.printDistanceVector /////////////////////////////////
    // Not in use as of right now!!!!!
    event void CommandHandler.printDistanceVector() {
    }

    ////////////////////////////////// CommandHandler.setTestServer /////////////////////////////////
    // Sets up a TCP server socket for incoming connections on the specified port
    event void CommandHandler.setTestServer(uint16_t port) {
        dbg(GENERAL_CHANNEL, "Spinning out a server for the TCP connection\n");
        call TCP.startServer(port);
    }

    ////////////////////////////////// CommandHandler.setTestClient /////////////////////////////////
    // Initiates a TCP client connection to the specified destination and port
    event void CommandHandler.setTestClient(uint16_t dest, uint16_t srcPort, 
                                            uint16_t destPort, uint16_t transfer) {
        dbg(GENERAL_CHANNEL, "Spinning out client for the TCP connection \n");
        call TCP.startClient(dest, srcPort, destPort, transfer);
    }

    ////////////////////////////////// CommandHandler.closeClient /////////////////////////////////
    // Closes a TCP client connection to a specified destination and port
    event void CommandHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
       // dbg(GENERAL_CHANNEL, "CLOSE_CLIENT EVENT\n");
        call TCP.closeClient(dest, srcPort, destPort);
        dbg(GENERAL_CHANNEL, "Client has been closed \n");
        dbg(GENERAL_CHANNEL, "All Flage been exchanged, SYN, SYN-ACK, ACK, and FIN \n");

    }

    event void CommandHandler.setAppServer() { }
    event void CommandHandler.setAppClient() { }

    ////////////////////////////////// makePack /////////////////////////////////
    // Assembles a packet structure from the provided parameters
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    ////////////////////////////////// randNum /////////////////////////////////
    // Generates a random number within a given range
    uint32_t randNum(uint32_t min, uint32_t max) {
        return (call Random.rand16() % (max - min + 1)) + min;
    }

    ////////////////////////////////// getSequence /////////////////////////////////
    // Increments and returns the current sequence number for packets
    uint16_t getSequence() {
        return current_seq++;
    }
}
