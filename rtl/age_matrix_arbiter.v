module age_matrix_arbiter#(
  parameter integer IS2_PRD_WIDTH = 6,
  parameter integer ENTRY_NUM = 16,  
  parameter integer AGE_W     = 8    
) (

  input  wire [ENTRY_NUM-1:0] valid_i,
  input  wire [AGE_W-1:0] age_i [ENTRY_NUM-1:0],   

  output reg [$clog2(ENTRY_NUM)-1:0] index_o,  
  output reg valid_o
);
  
  
function fifoid_lt(
    input [IS2_PRD_WIDTH:0]     a,
    input [IS2_PRD_WIDTH:0]     b
);
    fifoid_lt = ( (a[IS2_PRD_WIDTH] == b[IS2_PRD_WIDTH]) ?
                      (a[IS2_PRD_WIDTH-1:0] < b[IS2_PRD_WIDTH-1:0]) :
                      (a[IS2_PRD_WIDTH-1:0] > b[IS2_PRD_WIDTH-1:0]) );
endfunction

reg [ENTRY_NUM-1:0] oldest_vec;

always@(*)begin
    integer i,j;
    for(i=0;i<ENTRY_NUM;i=i+1) begin
        oldest_vec[i]=valid_i[i];
        if(valid_i[i])begin
            for(j=0;j<ENTRY_NUM;j=j+1) begin
                if(valid_i[j]) begin
                    if(fifoid_lt(age_i[j],age_i[i])) begin
                        oldest_vec[i]=1'b0;
                    end
                end
            end
        end
    end
end

always @(*) begin 
    integer i;
    index_o = 0;
    valid_o = 1'b0;

    for (i = 0; i < ENTRY_NUM; i=i+1) begin
      if (oldest_vec[i] && !valid_o) begin
        index_o = i[$clog2(ENTRY_NUM)-1:0];
        valid_o = 1'b1;
      end
    end
  end

endmodule