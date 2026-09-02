# AXI4-Lite Register Protocol Shell

This is a small AXI4-Lite slave implementation, split into one module per AXI channel, plus a top level that wires them together. It gives you a generic register style bus interface (WrAddr/WrData/WrStrb/WrEn and RdAddr/RdData) that any peripheral can sit behind.

## The idea

AXI4-Lite has five independent channels: write address, write data, write response, read address, and read data. Each channel here gets its own tiny module that just captures a transfer and holds it until something downstream is ready to use it. A separate pair of modules then combines the captured writes and reads into a simple internal bus that a real peripheral (registers, a peripheral's config space, etc) can respond to.

The design never assumes anything about what is behind that internal bus. It only knows how to talk AXI4-Lite on one side and a plain address/data bus on the other.

## Files

**parameters.svh**
Shared defines: address width, data width, byte strobe width, and register count. Everything else includes this file so widths stay consistent across the design.

**meds_s1_axil_aw_ch.sv**
Handles the write address channel. Waits for Awvalid, captures Awaddr into a register, and holds it (AwCaptured) until something pulses AwConsume to clear it. Simple two state machine: IDLE and CAPTURED.

**meds_s1_axil_w_ch.sv**
Same idea as meds_s1_axil_aw_ch but for the write data channel. Captures Wdata and Wstrb when Wvalid fires, holds them until WConsume clears the buffer.

**meds_s1_axil_b_ch.sv**
The write response channel, and also the module that actually commits a write. It waits until both the address and data channels have something captured (AwCaptured and WCaptured), pulls them together, pulses WrEn for one cycle to commit the write to the register storage behind it, checks WrAddrValid to decide between OKAY and DECERR, then raises Bvalid and waits for Bready.

**meds_s1_axil_ar_ch.sv**
The read address channel. Mirrors meds_s1_axil_aw_ch: captures Araddr when Arvalid fires and holds it until ArConsume clears it.

**meds_s1_axil_r_ch.sv**
The read data channel. Once an address has been captured, it presents that address on RdAddr, looks at the combinational RdData and RdAddrValid response, decides OKAY or DECERR, then raises Rvalid with the data and waits for Rready.

**meds_s1_axil_reg_protocol.sv**
The top level. Instantiates all five channel modules above and wires them together internally (aw/w feeding into b, ar feeding into r). It exposes the standard AXI4-Lite ports on one side, and a plain register style boundary (WrAddr, WrData, WrStrb, WrEn, WrAddrValid, RdAddr, RdData, RdAddrValid) on the other. This module does not know or care what peripheral is behind that boundary, so the exact same shell can front a UART, a timer, an accelerator's config space, or anything else.

**tb_axil_simple.sv**
A minimal testbench meant to be walked through out loud rather than to be exhaustive. It includes a small stand in peripheral called simple_regs, which is not part of the design, just a placeholder showing what a real register content module looks like. simple_regs has one real writable register at address 0x000 and one hardwired constant at address 0x004; anything else is out of range.

The testbench runs three scenarios:
1. Write a value to address 0x000, then read it back and check it matches.
2. Read address 0x004 and check it returns the hardwired constant, proving the RdAddr to RdData path works.
3. Read an address nobody owns (0x100) and check the bus correctly returns a DECERR response.

It also prints a cycle by cycle trace of both the AXI signals and the internal Wr/Rd signals, so you can see exactly what the shell is doing on each clock edge.

## How a write flows through the design

1. meds_s1_axil_aw_ch captures the address, meds_s1_axil_w_ch captures the data, independently and in any order.
2. Once both are captured, meds_s1_axil_b_ch consumes them both at once, drives WrAddr/WrData/WrStrb, and pulses WrEn for one cycle.
3. The peripheral behind the shell samples that pulse and updates its own state, and reports back WrAddrValid.
4. meds_s1_axil_b_ch turns that into Bresp (OKAY or DECERR) and raises Bvalid until the master accepts it with Bready.

## How a read flows through the design

1. meds_s1_axil_ar_ch captures the read address.
2. meds_s1_axil_r_ch consumes it, drives RdAddr, and looks at the combinational RdData/RdAddrValid coming back from the peripheral.
3. It turns that into Rresp and raises Rvalid with Rdata until the master accepts it with Rready.
