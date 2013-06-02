imp.configure("Access Imp", [], []);

local led1 = hardware.pin9; ///< First indicator on Sparkfun IMP breakout board
local led2 = hardware.pin8; ///< Second indicator on Sparkfun IMP breakout board

led1.configure(DIGITAL_OUT);
led1.write(1); // Note, the LEDs are active low so this is off
led2.configure(DIGITAL_OUT);
led2.write(1); // Note, the LEDs are active low so this is off

/// Tag scanning state machine
enum ScannerState {
    IDLE,
    SCANNING
}

/// Support enumeration for arfidReader class
enum GetPacketState {
    IDLE,
    HEADER,
    LENGTH,
    DATA,
    CHECKSUM
}

/// Class
class arfidReader {

    uartRcvSM = null; 
    uart = null;
    rcvPkt = null;
    moduleFirmwareVersion = null;
    GET_VERSION = [0x81];
    SEEK_FOR_TAG = [0x82];
    
    constructor(rfid_reader_uart) {
        uartRcvSM = GetPacketState.IDLE;
        uart = rfid_reader_uart;
        uart.configure(19200, 8, PARITY_NONE, 1, NO_CTSRTS, readCallback.bindenv(this));
        sendCommand(GET_VERSION);
        server.log("Arfid Reader initialized");
    }
    
    function readCallback() {
        local b = uart.read(); // Get first byte
        while (b != -1) {
            //server.log(uartRcvSM.tostring() + ", " + b.tostring());
            switch(uartRcvSM) {
                case GetPacketState.IDLE:
                    if (b == 0xff) uartRcvSM = GetPacketState.HEADER;
                    else {
                        server.log("Unexpected byte when looking for header1: " + b);
                        uartRcvSM = GetPacketState.IDLE;
                    }
                    break;
                case GetPacketState.HEADER:
                    if (b == 0x00) uartRcvSM = GetPacketState.LENGTH;
                    else {
                        server.log("Unexpected byte when looking for header2: " + b);
                        uartRcvSM = GetPacketState.IDLE;
                    }
                    break;
                case GetPacketState.LENGTH:
                    rcvPkt = [b];
                    uartRcvSM = GetPacketState.DATA;
                    break;
                case GetPacketState.DATA:
                    rcvPkt.append(b);
                    //server.log("Got byte " + (rcvPkt.len() - 1) + " of " + rcvPkt[0]);
                    if (rcvPkt.len() == (rcvPkt[0] + 1)) uartRcvSM = GetPacketState.CHECKSUM;
                    break;
                case GetPacketState.CHECKSUM:
                    if (b == checksum(rcvPkt)) processUARTPacket(rcvPkt);
                    else server.log("Bad UART packet checksum");
                    rcvPkt = null;
                    uartRcvSM = GetPacketState.IDLE;
            }
            b = uart.read(); // Get another byte
        }
    }
    
    /// Returns the checksum of a packet (not including header bytes).
    function checksum(pkt) {
        local sum = 0;
        foreach(b in pkt) sum += b;
        return sum & 0xff;
    }
    
    /// Accept a completed RFID reader module packet and decide what to do with it
    function processUARTPacket(packet) {
        switch(packet[1]) {
            case GET_VERSION[0]:
                server.log("RFID module has firmware version: " + packet.slice(1, packet.len()));
                moduleFirmwareVersion = packet;
                break;
            case SEEK_FOR_TAG[0]:
                if (packet[0] == 2) { // Start seeking response
                    if (packet[2] == 0x4c) server.log("SEEKING...");
                    else server.log("Error seeking tag: " + packet[2]);
                }
                else { // Found and selected a tag
                    local serno = 0
                    for (local i=4; i<packet.len(); i++) {
                        serno = (serno << 8) + packet[i];
                    }
                    server.log("Found tag of type " + packet[3] + ", serial number " + serno);
                }
                break;
            default:
                server.log("Unknown packet from RFID module: " + packet);
        }
    }
    
    
    /// Send a command to the RFID reader module.
    // @param cmd The command plus any data. Header, length and checksum are added by this function.
    function sendCommand(cmd) {
        uart.write(0xff);
        uart.write(0x00);
        uart.write(cmd.len());
        local csum = cmd.len(); // Length is the first byte added to the checksum
        foreach(b in cmd) {
            uart.write(b);
            csum += b;
        }
        uart.write(csum & 0xff);
    }
    
    /// Start seeking for a tag.
    function seek() {
        sendCommand(SEEK_FOR_TAG);
    }
}


reader <- arfidReader(hardware.uart57); /// Note, reader must be a permanent not a local variable or the garbage collector will eat it.

function mainPoll() {
    reader.seek();
    imp.wakeup(2.5, mainPoll);
}

imp.wakeup(0.5, mainPoll);
