imp.configure("Access Imp", [], []);

local led1 = hardware.pin9; ///< First indicator on Sparkfun IMP breakout board
local led2 = hardware.pin8; ///< Second indicator on Sparkfun IMP breakout board

led1.configure(DIGITAL_OUT);
led1.write(1); // Note, the LEDs are active low so this is off
led2.configure(DIGITAL_OUT);
led2.write(1); // Note, the LEDs are active low so this is off

/// Class
class arfidReader {
    
    uart = null;
    GET_VERSION = [0x81];
    
    constructor(rfid_reader_uart) {
        uart = rfid_reader_uart;
        uart.configure(19200, 8, PARITY_NONE, 1, NO_CTSRTS, readCallback.bindenv(this));
        sendCommand(GET_VERSION);
    }
    
    function readCallback() {
        local m = array(0); // Initalize empty array to hold the packet
        local b = uart.read(); // Get first byte
        while (b != -1) {
            m.append(b);
            b = uart.read(); // Get another byte
        }
        
        if (m.len() < 5) server.show("Packet too short " + m);
        else if (not (m[0] == 0xff and m[1] == 0x00)) server.show("Invalid packet header " + m[0] + m[1]);
        else server.show(m);
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
}


reader <- arfidReader(hardware.uart57); /// Note, reader must be a permanent not a local variable or the garbage collector will eat it.