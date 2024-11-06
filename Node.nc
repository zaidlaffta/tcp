
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

    uses interface Flooding;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface NeighborDiscovery;

    uses interface Timer<TMilli> as RoutingTimer;
    uses interface Routing;

    uses interface TCP;
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
                call Routing.send(&sendPackage);
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
                call Routing.recieve(myMsg);
            
            // TCP
            } else if (myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID) {
                call TCP.recieve(myMsg);

            // Regular Ping
            } else if (myMsg->dest == TOS_NODE_ID) {
                pingHandler(myMsg);
                
            // Neighbor Discovery
            } else if (myMsg->dest == AM_BROADCAST_ADDR) {
                call NeighborDiscovery.recieve(myMsg);

            // Not Destination
            } else {
                call Routing.send(myMsg);
            }
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

 
    event void NeighborTimer.fired() {
        call NeighborDiscovery.discover();
    }

    event void RoutingTimer.fired() {
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t numNeighbors = call NeighborDiscovery.numNeighbors();

        call Routing.updateNeighbors(neighbors, numNeighbors);
        call Routing.start();
    }

    event void TCP.route(pack* msg) {
        call Routing.send(msg);
    }

    /**
     * Called when the neighbor discovery  needs the sequence number for a packet
     *
     * @return the current sequence number
     */
    event uint16_t NeighborDiscovery.getSequence() {
        return getSequence();
    }


    event uint16_t Routing.getSequence() {
        return getSequence();
    }

    event uint16_t TCP.getSequence() {
        return getSequence();
    }

    /**
     * Called when simulation issues a ping command to the node
     */
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Routing.send(&sendPackage);
    }

    /**
     * Called when simulation issues a command to print the list of neighbor node IDs
     */
    event void CommandHandler.printNeighbors() {
        call NeighborDiscovery.printNeighbors();
    }

    /**
     * Called when simulation issues a command to print the routing table for this node
     */
    event void CommandHandler.printRouteTable() {
        call Routing.printRoutingTable();
    }

    event void CommandHandler.printLinkState(){ dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    /**
     * Same as printRouteTable()
     */
    event void CommandHandler.printDistanceVector() {
        call Routing.printRoutingTable();
    }

    /**
     * Called when simulation issues a command to listen for incomming connections on port 'port'
     * Creates a socket as a server
     */
    event void CommandHandler.setTestServer(uint16_t port) {
        dbg(GENERAL_CHANNEL, "TEST_SERVER EVENT\n");
        call TCP.startServer(port);
    }

    /**
     * Called when simulation issues a command to send 'transfer' bytes
     * from 'srcPort' to 'destPort' at node 'dest'
     * Creates a socket as a client
     */
    event void CommandHandler.setTestClient(uint16_t dest, uint16_t srcPort, 
                                            uint16_t destPort, uint16_t transfer) {
        dbg(GENERAL_CHANNEL, "TEST_CLIENT EVENT\n");
        call TCP.startClient(dest, srcPort, destPort, transfer);
    }

    /**
     * Called when simulation issues a command to close the connection 
     * from 'srcPort' to 'destPort' at node 'dest'
     */
    event void CommandHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        dbg(GENERAL_CHANNEL, "CLOSE_CLIENT EVENT\n");
        call TCP.closeClient(dest, srcPort, destPort);
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
