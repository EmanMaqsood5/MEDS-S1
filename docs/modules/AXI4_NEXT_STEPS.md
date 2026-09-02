# Next steps

This PR covers the generic AXI4 and AXI4-Lite fabric: channels, crossbar,
address decode, and the AXI4-Lite bridge. The following still need to be
added in follow-up work:

- Uncached DRAM alias in the address map (spec section 18.4)
- CLINT in the address map
- PLIC in the address map
- Debug ROM in the address map
- UART, SPI, GPIO, and Timer peripherals behind the AXI4-Lite bridge
- Accelerator MMIO windows for the sockets
- A decision on whether the crossbar should be hand-written or generated
  from configs/*.yaml, per rtl/fabric/README.md
- Full spec adaptation and conformance testing once the above land
