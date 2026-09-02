# AXI4 to AXI4-Lite Peripheral Bridge

This set of files builds a bridge that sits on a wide AXI4 backbone (256 bit data, 40 bit address, wide ID) and fans out to multiple smaller AXI4-Lite peripherals. It reuses the same capture buffer pattern from the plain AXI4-Lite package, just generalized so it can be used at any width and with an ID field.

## The idea

A crossbar or interconnect hands this bridge one wide AXI4 slave port. Behind that single port there can be several real peripherals (a timer, a UART, a GPIO block, and so on), each one small and AXI4-Lite based, each living in its own address window. The bridge's job is to capture an incoming AXI4 transaction, figure out which peripheral window the address falls in, translate the wide 256 bit access down to a 32 bit lane, forward it to the right peripheral as a plain AXI4-Lite transaction, and pass the response back up to the AXI4 side.

## Files

**axi4_params.svh**
Defines the wide AXI4 backbone widths: 40 bit address, 256 bit data, derived strobe width, and the ID width used on the crossbar's slave facing ports (the original ID plus the master index tag added by the crossbar).

**parameters.svh**
The narrow AXI4-Lite side widths, same as before: 12 bit address, 32 bit data, derived strobe width. This is the width each individual peripheral talks at.

**meds_s1_axi_addr_id_capture.sv**
A generic version of the "hold one address until consumed" buffer already used by meds_s1_axil_aw_ch and meds_s1_axil_ar_ch, but parameterized by address width and ID width instead of hardcoded to the AXI4-Lite widths, and it also captures an ID tag since AXI4 has one and AXI4-Lite does not. Same two state IDLE/CAPTURED behavior as before: accepts an address and ID when valid fires, holds them until a consume pulse clears the buffer.

**meds_s1_axi_wdata_capture.sv**
Same idea as meds_s1_axi_addr_id_capture but for write data. Generic version of meds_s1_axil_w_ch, parameterized by data and strobe width so it can hold a full 256 bit write beat instead of the narrow 32 bit one.

**meds_s1_axil_periph_subtree.sv**
The bridge itself. Sits on the AXI4 slave port, uses meds_s1_axi_addr_id_capture and meds_s1_axi_wdata_capture to grab an incoming write or read address (and write data), decodes which peripheral window the captured address falls into, picks out the correct 32 bit lane from the wide data word based on address bits 4:2, and then drives a plain AXI4-Lite master interface out to the selected peripheral. It waits for that peripheral's response, folds the 32 bit result back into the right lane of the wide read data bus, and returns it on the AXI4 side. If an address does not fall inside any peripheral's window, the bridge answers locally with a DECERR and never drives any peripheral. Each of the six peripheral slots has its own independently sized address window, set by localparams near the top of the file, so peripherals with more registers can get more room without resizing everyone else. The bridge does not care what real IP hangs off the peripheral ports, it just exposes a plain AXI4-Lite master interface per peripheral for real peripheral IP to be wired onto.

The write side and the read side are each their own small state machine (W_IDLE/W_DRIVE/W_BWAIT/W_BRESP and R_IDLE/R_DRIVE/R_RWAIT/R_RRESP), and only one write and one read transaction are in flight at a time, matching how the crossbar itself limits outstanding transactions per slave.

## Testbenches

**tb_axi_addr_id_capture.sv**
A focused conformance test for meds_s1_axi_addr_id_capture on its own, run at 40 bit address / 6 bit ID. Walks through basic capture, backpressure (offering a new address while one is already held must not overwrite it), consume clearing the buffer, the tricky case of a consume and a new valid arriving on the same cycle, several back to back capture and consume rounds, and reset while something is captured.

**tb_axi_wdata_capture.sv**
The same kind of focused test but for meds_s1_axi_wdata_capture, run at the real 256 bit data / 32 bit strobe width the bridge uses. Covers basic capture with a distinctive bit pattern (so a byte swap bug would actually show up), backpressure, consume, a partial strobe write held exactly as given, back to back rounds, and reset behavior.

**tb_axil_periph_subtree.sv**
An end to end demo of the whole bridge. It includes a tiny behavioral AXI4-Lite peripheral model (beh_axil_periph) that is not part of the real design, just a stand in with a small memory array, used six times to fill all six peripheral slots. Scenarios covered:
1. Write and read back within PERIPH0 at lane 0 of the wide data word.
2. Write and read back within PERIPH0 at a different lane, proving the addr[4:2] lane select logic actually works and not just the sub address decode.
3. Write and read back on PERIPH1, a different peripheral index, proving the address to peripheral decode really distinguishes peripherals.
4. Write and read back on each of the remaining four peripherals in turn, each with its own data pattern, proving all six slots are wired up correctly.
5. Access an address that falls inside no peripheral's window at all, expecting a DECERR straight from the bridge with no peripheral ever driven.
6. Checks that the AXI ID on the write response and read response matches the ID that was sent in on the address channel.

Like the earlier AXI4-Lite testbench, this one also prints a full cycle by cycle trace of both the AXI signals and the bridge's internal state so it lines up with a waveform.
