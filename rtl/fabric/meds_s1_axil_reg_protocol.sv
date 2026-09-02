
`include "parameters.svh"

module meds_s1_axil_reg_protocol (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    // Write address channel
    input  logic [`ADDR_WIDTH-1:0]      Awaddr,
    input  logic                        Awvalid,
    output logic                        Awready,

    // Write data channel
    input  logic [`DATA_WIDTH-1:0]      Wdata,
    input  logic [`STRB_WIDTH-1:0]      Wstrb,
    input  logic                        Wvalid,
    output logic                        Wready,

    // Write response channel
    output logic [1:0]                  Bresp,
    output logic                        Bvalid,
    input  logic                        Bready,

    // Read address channel
    input  logic [`ADDR_WIDTH-1:0]      Araddr,
    input  logic                        Arvalid,
    output logic                        Arready,

    // Read data channel
    output logic [`DATA_WIDTH-1:0]      Rdata,
    output logic [1:0]                  Rresp,
    output logic                        Rvalid,
    input  logic                        Rready,

    // ---------------- Generic register-content boundary ----------------
    // Whatever sits behind this shell
    // drives RdData/RdAddrValid combinationally off RdAddr,
    // and consumes WrAddr/WrData/WrStrb/WrEn, driving WrAddrValid back.
    output logic [`ADDR_WIDTH-1:0]      WrAddr,
    output logic [`DATA_WIDTH-1:0]      WrData,
    output logic [`STRB_WIDTH-1:0]      WrStrb,
    output logic                        WrEn,
    input  logic                        WrAddrValid,

    output logic [`ADDR_WIDTH-1:0]      RdAddr,
    input  logic [`DATA_WIDTH-1:0]      RdData,
    input  logic                        RdAddrValid
);

 
    wire [`ADDR_WIDTH-1:0] aw_captured_addr;
    wire                    aw_captured;
    wire                    aw_consume;

    wire [`DATA_WIDTH-1:0] w_captured_data;
    wire [`STRB_WIDTH-1:0] w_captured_strb;
    wire                    w_captured;
    wire                    w_consume;

   
    wire [`ADDR_WIDTH-1:0] ar_captured_addr;
    wire                    ar_captured;
    wire                    ar_consume;

    meds_s1_axil_aw_ch aw_ch_inst (
        .Aclk           (Aclk),
        .Aresetn        (Aresetn),

        .Awaddr         (Awaddr),
        .Awvalid        (Awvalid),
        .Awready        (Awready),

        .AwCapturedAddr (aw_captured_addr),
        .AwCaptured     (aw_captured),
        .AwConsume      (aw_consume)
    );

    meds_s1_axil_w_ch w_ch_inst (
        .Aclk          (Aclk),
        .Aresetn       (Aresetn),

        .Wdata         (Wdata),
        .Wstrb         (Wstrb),
        .Wvalid        (Wvalid),
        .Wready        (Wready),

        .WCapturedData (w_captured_data),
        .WCapturedStrb (w_captured_strb),
        .WCaptured     (w_captured),
        .WConsume      (w_consume)
    );

    meds_s1_axil_b_ch b_ch_inst (
        .Aclk           (Aclk),
        .Aresetn        (Aresetn),

        .AwCapturedAddr (aw_captured_addr),
        .AwCaptured     (aw_captured),
        .AwConsume      (aw_consume),

        .WCapturedData  (w_captured_data),
        .WCapturedStrb  (w_captured_strb),
        .WCaptured      (w_captured),
        .WConsume       (w_consume),

        .Bresp          (Bresp),
        .Bvalid         (Bvalid),
        .Bready         (Bready),

        .WrAddr         (WrAddr),
        .WrData         (WrData),
        .WrStrb         (WrStrb),
        .WrEn           (WrEn),
        .WrAddrValid    (WrAddrValid)
    );

    meds_s1_axil_ar_ch ar_ch_inst (
        .Aclk           (Aclk),
        .Aresetn        (Aresetn),

        .Araddr         (Araddr),
        .Arvalid        (Arvalid),
        .Arready        (Arready),

        .ArCapturedAddr (ar_captured_addr),
        .ArCaptured     (ar_captured),
        .ArConsume      (ar_consume)
    );

    meds_s1_axil_r_ch r_ch_inst (
        .Aclk           (Aclk),
        .Aresetn        (Aresetn),

        .ArCapturedAddr (ar_captured_addr),
        .ArCaptured     (ar_captured),
        .ArConsume      (ar_consume),

        .Rdata          (Rdata),
        .Rresp          (Rresp),
        .Rvalid         (Rvalid),
        .Rready         (Rready),

        .RdAddr         (RdAddr),
        .RdData         (RdData),
        .RdAddrValid    (RdAddrValid)
    );

endmodule
