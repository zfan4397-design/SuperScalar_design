// Dependency scaffold for rs_lsu_queue; core arbitration is intentionally TODO.
// Reference: D:/zz/superscalercore/vsrc/utils/age_matrix_arbiter.sv
`include "config_pkg.vh"
// ============================================================================
// module: age_matrix_arbiter
// ============================================================================

module age_matrix_arbiter #(
  // ----------------------------------------------------------------------------
  // PARAMETERS
  // ----------------------------------------------------------------------------
  parameter ENTRY_NUM = 16,  
  parameter AGE_W     = 8    
) (
  // ----------------------------------------------------------------------------
  // PORTS
  // ----------------------------------------------------------------------------
  input wire [ENTRY_NUM-1:0]           valid_i,
  input wire [ENTRY_NUM*AGE_W-1:0] age_i,   

  output reg [$clog2(ENTRY_NUM)-1:0]   index_o,  
  output reg                           valid_o   
);

  // ----------------------------------------------------------------------------
  // REGISTERS 
  // ----------------------------------------------------------------------------
  reg [ENTRY_NUM-1:0] oldest_vec;

  `include "fifoid_functions.vh"

  // ----------------------------------------------------------------------------
  // COMBINATIONAL LOGIC
  // ----------------------------------------------------------------------------
  always @* begin : proc_1
      integer i;
      integer j;
    for (i = 0; i < ENTRY_NUM; i = i + 1) begin
      oldest_vec[i] = valid_i[i];

      if (valid_i[i]) begin
        for (j = 0; j < ENTRY_NUM; j = j + 1) begin
          if (valid_i[j]) begin
            if (fifoid_lt(age_i[(j)*AGE_W +: AGE_W], age_i[(i)*AGE_W +: AGE_W])) begin
              oldest_vec[i] = 1'b0;
            end
          end
        end
      end
    end
  end

  always @* begin : proc_2
      integer i;
    index_o = 0;
    valid_o = 1'b0;

    for (i = 0; i < ENTRY_NUM; i = i + 1) begin
      if (oldest_vec[i] && !valid_o) begin
        index_o = i[$clog2(ENTRY_NUM)-1:0];
        valid_o = 1'b1;
      end
    end
  end

endmodule
