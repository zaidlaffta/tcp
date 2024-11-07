from TestSim import TestSim

def setup_simulation():
    """Initializes and sets up the simulation environment."""
    sim = TestSim()
    sim.runTime(1)  # Simulate the network being off initially.
    sim.loadTopo("long_line.topo")  # Load network topology.
    sim.loadNoise("meyer-heavy.txt")  # Add noise model to motes.
    sim.bootAll()  # Boot all sensors.

    # Add primary communication channels
    channels = [sim.COMMAND_CHANNEL, sim.GENERAL_CHANNEL, sim.TRANSPORT_CHANNEL]
    for channel in channels:
        sim.addChannel(channel)
    
    sim.runTime(100)  # Allow routing tables to settle.
    return sim

def perform_client_server_test(sim):
    """Conducts server setup and client-server data transfer test."""
    try:
        # Set up the server
        sim.testServer(address=7, port=80)
        sim.runTime(5)

        # Client initiates data transfer to the server
        sim.testClient(clientAddress=3, dest=7, srcPort=20, destPort=80, transfer=12)
        sim.runTime(5)

        # Close the client connection
        sim.closeClient(clientAddress=3, dest=7, srcPort=20, destPort=80)
        sim.runTime(5)
    except Exception as e:
        print("An error occurred during client-server testing: {}".format(e))

def main():
    sim = setup_simulation()  # Initialize simulation setup
    perform_client_server_test(sim)  # Run client-server test sequence

if __name__ == '__main__':
    main()
