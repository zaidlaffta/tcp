
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface Random as Random;

    uses interface CommandHandler;

    uses interface FloodingHandler;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface NeighborDiscoveryHandler;

    uses interface Timer<TMilli> as RoutingTimer;
    uses interface RoutingHandler;

    uses interface TCPHandler;
}

implementation{
    // Global Variables
    pack sendPackage;                   // Generic packet used to hold the next packet to be sent
    uint16_t current_seq = 1;           // Sequence number of packets sent by node

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void pingHandler(pack* msg);
    uint32_t randNum(uint32_t min, uint32_t max);
    uint16_t getSequence();

   
    event void Boot.booted(){
        call AMControl.start();
        call NeighborTimer.startPeriodic( randNum(10000, 20000) );
        call RoutingTimer.startPeriodic( randNum(25000, 35000) );
        
        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    /**
     * Starts radio, called during boot
     */
    event void AMControl.startDone(error_t err){
        if (err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    void pingHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(GENERAL_CHANNEL, "--- Ping recieved from %d\n", msg->src);
                dbg(GENERAL_CHANNEL, "--- Packet Payload: %s\n", msg->payload);
                dbg(GENERAL_CHANNEL, "--- Sending Reply...\n");
                makePack(&sendPackage, msg->dest, msg->src, MAX_TTL, PROTOCOL_PINGREPLY, current_seq++, (uint8_t*)msg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call RoutingHandler.send(&sendPackage);
                break;
                    
            case PROTOCOL_PINGREPLY:
                dbg(GENERAL_CHANNEL, "--- Ping reply recieved from %d\n", msg->src);
                break;
                    
            default:
                dbg(GENERAL_CHANNEL, "Unrecognized ping protocol: %d\n", msg->protocol);
        }
    }

    
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

        if (len == sizeof(pack)) {
            pack* myMsg=(pack*) payload;

            // Check TTL
            if (myMsg->TTL-- == 0) {
                return msg;
            }

            // Distance Vector
            if (myMsg->protocol == PROTOCOL_DV) {
                call RoutingHandler.recieve(myMsg);
            
            // TCP
            } else if (myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID) {
                call TCPHandler.recieve(myMsg);

            // Regular Ping
            } else if (myMsg->dest == TOS_NODE_ID) {
                pingHandler(myMsg);
                
            // Neighbor Discovery
            } else if (myMsg->dest == AM_BROADCAST_ADDR) {
                call NeighborDiscoveryHandler.recieve(myMsg);

            // Not Destination
            } else {
                call RoutingHandler.send(myMsg);
            }
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

 
    event void NeighborTimer.fired() {
        call NeighborDiscoveryHandler.discover();
    }

    event void RoutingTimer.fired() {
        uint32_t* neighbors = call NeighborDiscoveryHandler.getNeighbors();
        uint16_t numNeighbors = call NeighborDiscoveryHandler.numNeighbors();

        call RoutingHandler.updateNeighbors(neighbors, numNeighbors);
        call RoutingHandler.start();
    }

    event void TCPHandler.route(pack* msg) {
        call RoutingHandler.send(msg);
    }

    /**
     * Called when the neighbor discovery handler needs the sequence number for a packet
     *
     * @return the current sequence number
     */
    event uint16_t NeighborDiscoveryHandler.getSequence() {
        return getSequence();
    }


    event uint16_t RoutingHandler.getSequence() {
        return getSequence();
    }

    event uint16_t TCPHandler.getSequence() {
        return getSequence();
    }

    /**
     * Called when simulation issues a ping command to the node
     */
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call RoutingHandler.send(&sendPackage);
    }

    /**
     * Called when simulation issues a command to print the list of neighbor node IDs
     */
    event void CommandHandler.printNeighbors() {
        call NeighborDiscoveryHandler.printNeighbors();
    }

    /**
     * Called when simulation issues a command to print the routing table for this node
     */
    event void CommandHandler.printRouteTable() {
        call RoutingHandler.printRoutingTable();
    }

    event void CommandHandler.printLinkState(){ dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    /**
     * Same as printRouteTable()
     */
    event void CommandHandler.printDistanceVector() {
        call RoutingHandler.printRoutingTable();
    }

    /**
     * Called when simulation issues a command to listen for incomming connections on port 'port'
     * Creates a socket as a server
     */
    event void CommandHandler.setTestServer(uint16_t port) {
        dbg(GENERAL_CHANNEL, "TEST_SERVER EVENT\n");
        call TCPHandler.startServer(port);
    }

    /**
     * Called when simulation issues a command to send 'transfer' bytes
     * from 'srcPort' to 'destPort' at node 'dest'
     * Creates a socket as a client
     */
    event void CommandHandler.setTestClient(uint16_t dest, uint16_t srcPort, 
                                            uint16_t destPort, uint16_t transfer) {
        dbg(GENERAL_CHANNEL, "TEST_CLIENT EVENT\n");
        call TCPHandler.startClient(dest, srcPort, destPort, transfer);
    }

    /**
     * Called when simulation issues a command to close the connection 
     * from 'srcPort' to 'destPort' at node 'dest'
     */
    event void CommandHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        dbg(GENERAL_CHANNEL, "CLOSE_CLIENT EVENT\n");
        call TCPHandler.closeClient(dest, srcPort, destPort);
    }

    event void CommandHandler.setAppServer(){ dbg(GENERAL_CHANNEL, "setAppServer\n"); }

    event void CommandHandler.setAppClient(){ dbg(GENERAL_CHANNEL, "setAppClient\n"); }

    /**
     * Assembles a packet given by the first parameter using the other parameters
     */
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    /**
     * Generates a random 16-bit number between 'min' and 'max'
     */
    uint32_t randNum(uint32_t min, uint32_t max) {
        return ( call Random.rand16() % (max-min+1) ) + min;
    }

    /**
     * Gets the current sequence number, automatically increments it
     *
     * @return the current sequence number
     */
    uint16_t getSequence() {
        return current_seq++;
    }
}
