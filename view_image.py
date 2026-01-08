import serial
import time

# Thay 'COMx' bằng cổng COM của module USB-TTL bạn cắm vào
ser = serial.Serial('COM3', 115200, timeout=1)

print("Dang cho anh tu FPGA...")
while True:
    if ser.in_waiting:
        # Đọc dữ liệu và in ra, cứ 28 ký tự xuống dòng 1 lần
        chunk = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
        for char in chunk:
            print(char, end='')
            # Logic đếm để xuống dòng (bạn có thể tự căn chỉnh bằng mắt)
