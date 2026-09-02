// ============================================================================
// meds_s1_axi4_ar_ch.sv
//
// Full-AXI4 read-address channel capture, one outstanding AR at a time
// (matches the crossbar's r_inflight policy,). Same shape as
// meds_s1_axi4_aw_ch.sv / axi4lite/meds_s1_axil_ar_ch.sv. WRAP bursts are captured
// verbatim like any other burst; the wrapping address arithmetic lives
// downstream in meds_s1_axi4_r_ch (see that file's header).
// ============================================================================
`include "axi4_params.svh"

module meds_s1_axi4_ar_ch #(
    parameter int ID_W = `AXI_ID_W // widened to AXI_SID_W when instantiated behind meds_s1_axi4_crossbar
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [ID_W-1:0] arid,
    input logic [`AXI_ADDR_W-1:0] araddr,
    input logic [7:0] arlen,
    input logic [2:0] arsize,
    input logic [1:0] arburst,
    input logic arvalid,
    output logic arready,

    output logic [ID_W-1:0] ArCapturedId,
    output logic [`AXI_ADDR_W-1:0] ArCapturedAddr,
    output logic [7:0] ArCapturedLen,
    output logic [2:0] ArCapturedSize,
    output logic [1:0] ArCapturedBurst,
    output logic ArCaptured,
    input logic ArConsume // pulse: clear the buffer
);

    localparam [0:0] IDLE = 1'd0,
                      CAPTURED = 1'd1;

    logic state, state_n;
    logic [ID_W-1:0] id_reg, id_reg_n;
    logic [`AXI_ADDR_W-1:0] addr_reg, addr_reg_n;
    logic [7:0] len_reg, len_reg_n;
    logic [2:0] size_reg, size_reg_n;
    logic [1:0] burst_reg, burst_reg_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            id_reg <= '0;
            addr_reg <= '0;
            len_reg <= '0;
            size_reg <= '0;
            burst_reg <= '0;
        end else begin
            state <= state_n;
            id_reg <= id_reg_n;
            addr_reg <= addr_reg_n;
            len_reg <= len_reg_n;
            size_reg <= size_reg_n;
            burst_reg <= burst_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        id_reg_n = id_reg;
        addr_reg_n = addr_reg;
        len_reg_n = len_reg;
        size_reg_n = size_reg;
        burst_reg_n = burst_reg;

        arready = 1'b0;

        case (state)

            IDLE: begin
                arready = 1'b1;
                if (arvalid) begin
                    id_reg_n = arid;
                    addr_reg_n = araddr;
                    len_reg_n = arlen;
                    size_reg_n = arsize;
                    burst_reg_n = arburst;
                    state_n = CAPTURED;
                end
            end

            CAPTURED: begin
                arready = 1'b0;
                if (ArConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign ArCapturedId = id_reg;
    assign ArCapturedAddr = addr_reg;
    assign ArCapturedLen = len_reg;
    assign ArCapturedSize = size_reg;
    assign ArCapturedBurst = burst_reg;
    assign ArCaptured = (state == CAPTURED);

endmodule
