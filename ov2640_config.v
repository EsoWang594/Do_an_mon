module ov2640_config (
    input  wire clk,        // 50MHz Clock
    input  wire rst_n,      // Reset active low
    output reg  sioc,       // SCL (Clock I2C)
    inout  wire siod,       // SDA (Data I2C)
    output reg  config_done // 1 = Cấu hình xong
);

    // Địa chỉ I2C của OV2640 (Write Address)
    localparam CAMERA_ADDR = 8'h60; 
    
    reg [7:0] reg_addr;
    reg [7:0] reg_data;
    reg [7:0] rom_addr;
    
    // --- BẢNG CẤU HÌNH (ROM) - Tối ưu cho QVGA RGB565 ---
    // Logic: Chọn Bank -> Reset -> Setup Sensor -> Chọn Bank -> Setup DSP
    always @(*) begin
        case (rom_addr)
            // 1. BANK SELECT & RESET
            8'd0 : {reg_addr, reg_data} = {8'hFF, 8'h01}; // Select Bank 1
            8'd1 : {reg_addr, reg_data} = {8'h12, 8'h80}; // Reset All
            
            // 2. SENSOR SETTINGS (QVGA Windowing)
            8'd2 : {reg_addr, reg_data} = {8'hFF, 8'h01}; // Confirm Bank 1
            8'd3 : {reg_addr, reg_data} = {8'h17, 8'h11}; // HREF start
            8'd4 : {reg_addr, reg_data} = {8'h18, 8'h43}; // HREF end
            8'd5 : {reg_addr, reg_data} = {8'h19, 8'h00}; // VSTRT
            8'd6 : {reg_addr, reg_data} = {8'h1A, 8'h25}; // VEND
            8'd7 : {reg_addr, reg_data} = {8'h32, 8'h36}; // Pixel Clock Div
            8'd8 : {reg_addr, reg_data} = {8'h03, 8'h0F}; // COM1 (Auto Exposure)
            
            // 3. DSP SETTINGS (Output Format)
            8'd9 : {reg_addr, reg_data} = {8'hFF, 8'h00}; // Select Bank 0
            8'd10: {reg_addr, reg_data} = {8'hC7, 8'h00}; // Normal mode
            8'd11: {reg_addr, reg_data} = {8'hDA, 8'h10}; // DISABLE JPEG, ENABLE RAW
            8'd12: {reg_addr, reg_data} = {8'hD7, 8'h03}; 
            8'd13: {reg_addr, reg_data} = {8'h50, 8'h80}; 
            8'd14: {reg_addr, reg_data} = {8'h5A, 8'h50}; 
            8'd15: {reg_addr, reg_data} = {8'h5B, 8'h78}; 
            8'd16: {reg_addr, reg_data} = {8'h5C, 8'h01}; // Width High
            8'd17: {reg_addr, reg_data} = {8'h5D, 8'h00}; // Height High
            8'd18: {reg_addr, reg_data} = {8'hE0, 8'h04}; 
            8'd19: {reg_addr, reg_data} = {8'h55, 8'h00}; // Brightness
            
            default: {reg_addr, reg_data} = {8'hFF, 8'hFF}; // Kết thúc
        endcase
    end
    
    // --- LOGIC GỬI I2C (SCCB Engine) ---
    // Phần này thiếu trong file gốc của bạn
    
    reg i2c_tick;
    reg [15:0] clk_cnt;
    reg [5:0] state;
    reg [3:0] bit_cnt;
    reg siod_out;
    reg siod_dir; // 1: Output, 0: Input (Tri-state)
    
    assign siod = siod_dir ? siod_out : 1'bz;

    // Tạo xung chậm ~200kHz từ 50MHz
    always @(posedge clk) begin
        if (clk_cnt >= 250) begin 
            clk_cnt <= 0; i2c_tick <= ~i2c_tick; 
        end else clk_cnt <= clk_cnt + 1;
    end

    // Máy trạng thái gửi lệnh
    always @(posedge i2c_tick or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0; rom_addr <= 0; config_done <= 0;
            sioc <= 1; siod_dir <= 1; siod_out <= 1;
        end else begin
            case (state)
                0: begin // IDLE
                    sioc <= 1; siod_out <= 1;
                    if (rom_addr == 20) config_done <= 1; // Số lệnh = 20
                    else begin state <= 1; config_done <= 0; end
                end
                
                // Start Condition
                1: begin siod_out <= 0; state <= 2; end
                2: begin sioc <= 0; state <= 3; bit_cnt <= 0; end
                
                // Send Device Address
                3: begin siod_out <= CAMERA_ADDR[7-bit_cnt]; state <= 4; end
                4: begin sioc <= 1; state <= 5; end
                5: begin sioc <= 0; 
                    if(bit_cnt==7) begin bit_cnt<=0; state<=6; end 
                    else begin bit_cnt<=bit_cnt+1; state<=3; end 
                end
                
                // Ack
                6: begin siod_dir <= 0; sioc <= 1; state <= 7; end 
                7: begin sioc <= 0; siod_dir <= 1; state <= 8; end

                // Send Register Address
                8: begin siod_out <= reg_addr[7-bit_cnt]; state <= 9; end
                9: begin sioc <= 1; state <= 10; end
                10:begin sioc <= 0; 
                    if(bit_cnt==7) begin bit_cnt<=0; state<=11; end 
                    else begin bit_cnt<=bit_cnt+1; state<=8; end 
                end
                11:begin siod_dir <= 0; sioc <= 1; state <= 12; end // Ack
                12:begin sioc <= 0; siod_dir <= 1; state <= 13; end

                // Send Register Data
                13:begin siod_out <= reg_data[7-bit_cnt]; state <= 14; end
                14:begin sioc <= 1; state <= 15; end
                15:begin sioc <= 0; 
                    if(bit_cnt==7) begin bit_cnt<=0; state<=16; end 
                    else begin bit_cnt<=bit_cnt+1; state<=13; end 
                end
                16:begin siod_dir <= 0; sioc <= 1; state <= 17; end // Ack
                17:begin sioc <= 0; siod_dir <= 1; state <= 18; end

                // Stop Condition
                18:begin siod_out <= 0; state <= 19; end
                19:begin sioc <= 1; state <= 20; end
                20:begin siod_out <= 1; state <= 21; end
                21:begin rom_addr <= rom_addr + 1; state <= 0; end // Next Command
            endcase
        end
    end
endmodule