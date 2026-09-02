

`include "parameters.svh"

module meds_s1_axil_ar_ch (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    input  logic [`ADDR_WIDTH-1:0]      Araddr,
    input  logic                        Arvalid,
    output logic                        Arready,

    output logic [`ADDR_WIDTH-1:0]      ArCapturedAddr,
    output logic                        ArCaptured,
    input  logic                        ArConsume   // pulse: clear the buffer
);

    localparam [0:0] IDLE     = 1'd0,
                      CAPTURED = 1'd1;

    reg                     state, state_n;
    reg [`ADDR_WIDTH-1:0]  addr_reg, addr_reg_n;

    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn) begin
            state    <= IDLE;
            addr_reg <= 0;
        end else begin
            state    <= state_n;
            addr_reg <= addr_reg_n;
        end
    end

    always @(*) begin
        state_n    = state;
        addr_reg_n = addr_reg;

        Arready = 1'b0;

        case (state)

            IDLE: begin
                Arready = 1'b1;
                if (Arvalid) begin
                    addr_reg_n = Araddr;
                    state_n    = CAPTURED;
                end
            end

            CAPTURED: begin
                Arready = 1'b0;
                if (ArConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign ArCapturedAddr = addr_reg;
    assign ArCaptured     = (state == CAPTURED);

endmodule
