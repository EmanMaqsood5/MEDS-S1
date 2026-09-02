

`include "parameters.svh"


module simple_regs (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    input  logic [`ADDR_WIDTH-1:0]      WrAddr,
    input  logic [`DATA_WIDTH-1:0]      WrData,
    input  logic [`STRB_WIDTH-1:0]      WrStrb,
    input  logic                        WrEn,
    output logic                        WrAddrValid,

    input  logic [`ADDR_WIDTH-1:0]      RdAddr,
    output logic [`DATA_WIDTH-1:0]      RdData,
    output logic                        RdAddrValid
);
    localparam [`ADDR_WIDTH-1:0] ADDR_RW    = 12'h000; // the only writable register
    localparam [`ADDR_WIDTH-1:0] ADDR_CONST = 12'h004; // a fixed, hardwired value
    localparam [31:0]            CONST_VAL  = 32'hABCD_1234;

    // The only two addresses this peripheral responds to.
    function automatic is_valid(input [`ADDR_WIDTH-1:0] a);
        is_valid = (a == ADDR_RW) || (a == ADDR_CONST);
    endfunction

    assign WrAddrValid = is_valid(WrAddr);
    assign RdAddrValid = is_valid(RdAddr);

    
    reg [31:0] rw_reg;
    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn)
            rw_reg <= 32'h0;
        else if (WrEn && WrAddr == ADDR_RW)
            rw_reg <= WrData; 
    end

    
    always @(*) begin
        if (RdAddr == ADDR_RW)
            RdData = rw_reg;      // real stored value
        else if (RdAddr == ADDR_CONST)
            RdData = CONST_VAL;   // hardwired constant
        else
            RdData = 32'hDEAD_BEEF; // nobody home
    end

endmodule


module tb_axil_simple;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    reg Aclk = 0;
    reg Aresetn = 0;
    always #5 Aclk = ~Aclk;

    reg  [`ADDR_WIDTH-1:0] Awaddr;
    reg                     Awvalid;
    wire                    Awready;
    reg  [`DATA_WIDTH-1:0] Wdata;
    reg  [`STRB_WIDTH-1:0] Wstrb;
    reg                     Wvalid;
    wire                    Wready;
    wire [1:0]              Bresp;
    wire                    Bvalid;
    reg                     Bready;
    reg  [`ADDR_WIDTH-1:0] Araddr;
    reg                     Arvalid;
    wire                    Arready;
    wire [`DATA_WIDTH-1:0] Rdata;
    wire [1:0]              Rresp;
    wire                    Rvalid;
    reg                     Rready;

    wire [`ADDR_WIDTH-1:0] wr_addr;
    wire [`DATA_WIDTH-1:0] wr_data;
    wire [`STRB_WIDTH-1:0] wr_strb;
    wire                    wr_en;
    wire                    wr_addr_valid;
    wire [`ADDR_WIDTH-1:0] rd_addr;
    wire [`DATA_WIDTH-1:0] rd_data;
    wire                    rd_addr_valid;

    integer errors = 0;

    
    meds_s1_axil_reg_protocol dut (
        .Aclk(Aclk), .Aresetn(Aresetn),
        .Awaddr(Awaddr), .Awvalid(Awvalid), .Awready(Awready),
        .Wdata(Wdata), .Wstrb(Wstrb), .Wvalid(Wvalid), .Wready(Wready),
        .Bresp(Bresp), .Bvalid(Bvalid), .Bready(Bready),
        .Araddr(Araddr), .Arvalid(Arvalid), .Arready(Arready),
        .Rdata(Rdata), .Rresp(Rresp), .Rvalid(Rvalid), .Rready(Rready),
        .WrAddr(wr_addr), .WrData(wr_data), .WrStrb(wr_strb), .WrEn(wr_en),
        .WrAddrValid(wr_addr_valid),
        .RdAddr(rd_addr), .RdData(rd_data), .RdAddrValid(rd_addr_valid)
    );

    simple_regs u_regs (
        .Aclk(Aclk), .Aresetn(Aresetn),
        .WrAddr(wr_addr), .WrData(wr_data), .WrStrb(wr_strb), .WrEn(wr_en),
        .WrAddrValid(wr_addr_valid),
        .RdAddr(rd_addr), .RdData(rd_data), .RdAddrValid(rd_addr_valid)
    );

    // ---- reset ----
    initial begin
        Awaddr <= 0; Awvalid <= 0;
        Wdata  <= 0; Wstrb  <= 0; Wvalid <= 0;
        Bready <= 0;
        Araddr <= 0; Arvalid <= 0;
        Rready <= 0;

        Aresetn = 0;
        repeat (4) @(posedge Aclk);
        Aresetn = 1;
        @(posedge Aclk);
    end

    
    integer cycle_num = 0;
    initial begin
        @(posedge Aresetn);
        forever begin
            @(posedge Aclk);
            #1;
            cycle_num = cycle_num + 1;
            $display("-------------------------------------------------------------");
            $display("[cycle %0d]", cycle_num);
            $display("  AXI : AWaddr=%h AWvalid=%b AWready=%b | Wdata=%h Wvalid=%b Wready=%b | Bresp=%0d Bvalid=%b",
                      Awaddr, Awvalid, Awready, Wdata, Wvalid, Wready, Bresp, Bvalid);
            $display("  AXI : ARaddr=%h ARvalid=%b ARready=%b | Rdata=%h Rresp=%0d Rvalid=%b",
                      Araddr, Arvalid, Arready, Rdata, Rresp, Rvalid);
            $display("  INT : RdAddr=%h -> RdData=%h (RdAddrValid=%b)   WrAddr=%h WrEn=%b -> writing %h (WrAddrValid=%b)",
                      rd_addr, rd_data, rd_addr_valid, wr_addr, wr_en, wr_data, wr_addr_valid);
        end
    end

    
    task axil_write(input [`ADDR_WIDTH-1:0] addr, input [`DATA_WIDTH-1:0] data, output [1:0] resp);
        begin
            @(posedge Aclk);
            Awaddr <= addr; Awvalid <= 1'b1;
            Wdata  <= data; Wstrb <= 4'hF; Wvalid <= 1'b1;
            @(posedge Aclk);
            while (!(Awready && Wready)) @(posedge Aclk);
            Awvalid <= 1'b0; Wvalid <= 1'b0;

            Bready <= 1'b1;
            @(posedge Aclk);
            while (!Bvalid) @(posedge Aclk);
            resp = Bresp;
            Bready <= 1'b0;
        end
    endtask

    task axil_read(input [`ADDR_WIDTH-1:0] addr, output [`DATA_WIDTH-1:0] data, output [1:0] resp);
        begin
            @(posedge Aclk);
            Araddr <= addr; Arvalid <= 1'b1;
            @(posedge Aclk);
            while (!Arready) @(posedge Aclk);
            Arvalid <= 1'b0;

            Rready <= 1'b1;
            @(posedge Aclk);
            while (!Rvalid) @(posedge Aclk);
            data = Rdata;
            resp = Rresp;
            Rready <= 1'b0;
        end
    endtask

    task check_eq(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("[FAIL] %0s: got=0x%08h expected=0x%08h", name, got, exp);
                errors = errors + 1;
            end else
                $display("[PASS] %0s: 0x%08h", name, got);
        end
    endtask

    reg [31:0] rd;
    reg [1:0]  resp;

    initial begin
        @(posedge Aresetn);
        repeat (2) @(posedge Aclk);

        $display("");
        $display("### SCENARIO 1: write 0x11223344 to address 0x000, read it back ###");
        axil_write(12'h000, 32'h1122_3344, resp);
        check_eq("write resp == OKAY", {30'b0, resp}, {30'b0, RESP_OKAY});
        axil_read(12'h000, rd, resp);
        check_eq("readback matches what we wrote", rd, 32'h1122_3344);

        $display("");
        $display("### SCENARIO 2: read address 0x004, a hardwired constant we never wrote ###");
        axil_read(12'h004, rd, resp);
        check_eq("constant register returns fixed value", rd, 32'hABCD_1234);

        $display("");
        $display("### SCENARIO 3: access address 0x100, which nobody owns -> DECERR ###");
        axil_read(12'h100, rd, resp);
        check_eq("out-of-range read resp == DECERR", {30'b0, resp}, {30'b0, RESP_DECERR});
        check_eq("out-of-range read data is the default filler", rd, 32'hDEAD_BEEF);

        repeat (3) @(posedge Aclk);
        $display("");
        if (errors == 0) begin
            $display("=============================================");
            $display(" ALL TESTS PASSED");
            $display("=============================================");
        end else begin
            $display("=============================================");
            $display(" %0d TEST(S) FAILED", errors);
            $display("=============================================");
        end
        $finish;
    end

    initial begin
        #5000;
        $display("[TIMEOUT] testbench did not finish");
        $finish;
    end

endmodule
