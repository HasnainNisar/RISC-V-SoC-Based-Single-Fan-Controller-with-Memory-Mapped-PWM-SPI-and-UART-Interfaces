# Memory Map — RISC-V SoC Single-Fan Controller

## 1. Top-Level Address Map

| Region              | Start Address | End Address   | Size   | Notes                          |
|---------------------|----------------|---------------|--------|---------------------------------|
| Instruction SRAM     | 0x0000_0000    | 0x0000_0FFF   | 4 KB   | Preloaded by testbench (IMEM)  |
| Data SRAM             | 0x1000_0000    | 0x1000_0FFF   | 4 KB   | General-purpose R/W (DMEM)     |
| Config SRAM            | 0x2000_0000    | 0x2000_00FF   | 256 B  | Fan profiles, thresholds       |
| PWM Controller          | 0x3000_0000    | 0x3000_000F   | 16 B   | See Section 3                  |
| SPI Master               | 0x3000_1000    | 0x3000_100F   | 16 B   | See Section 4                  |
| UART Tx/Rx                | 0x3000_2000    | 0x3000_200F   | 16 B   | See Section 5                  |

Address decoding is done on bits [31:28] primarily, with peripheral
sub-selection on bits [15:12] for the 0x3000_xxxx region.

```
Address[31:28]:
  0x0 -> Instruction SRAM
  0x1 -> Data SRAM
  0x2 -> Config SRAM
  0x3 -> Peripheral region (further decoded by [15:12])
        0x0 -> PWM
        0x1 -> SPI
        0x2 -> UART
```

## 2. Core Bus Rules

- All accesses are 32-bit word-aligned (address[1:0] must be 00).
- Core issues: `addr`, `wdata`, `we` (write enable), `re` (read enable).
- Selected peripheral/memory returns `rdata` and, where applicable,
  `ready`/`error` status.
- Unmapped address access -> bus returns `error = 1`, `rdata = 0xDEAD_BEEF`.

## 3. PWM Controller Registers (Base = 0x3000_0000)

| Offset | Name        | Access | Bits Used | Description                                  |
|--------|-------------|--------|-----------|-----------------------------------------------|
| 0x0    | PWM_CTRL    | R/W    | [0]=EN, [1]=RESET | Enable PWM, soft reset PWM logic     |
| 0x4    | PWM_DUTY    | R/W    | [7:0]     | Duty cycle value (0-255, 0=0%, 255≈100%) |
| 0x8    | PWM_STATUS  | R      | [0]=RUNNING, [1]=FAULT | Fan running / stall fault flag  |
| 0xC    | PWM_RPM     | R      | [15:0]    | Simulated RPM reading from fan model     |

## 4. SPI Master Registers (Base = 0x3000_1000)

| Offset | Name        | Access | Bits Used | Description                                  |
|--------|-------------|--------|-----------|-----------------------------------------------|
| 0x0    | SPI_CTRL    | R/W    | [0]=START, [2:1]=CLKDIV | Start transfer, clock divider   |
| 0x4    | SPI_TXDATA  | W      | [7:0]     | Byte to transmit (MOSI)                  |
| 0x8    | SPI_RXDATA  | R      | [7:0]     | Byte received (MISO)                     |
| 0xC    | SPI_STATUS  | R      | [0]=BUSY, [1]=DONE, [2]=ERROR | Transfer status              |

## 5. UART Registers (Base = 0x3000_2000)

| Offset | Name        | Access | Bits Used | Description                                  |
|--------|-------------|--------|-----------|-----------------------------------------------|
| 0x0    | UART_CTRL   | R/W    | [0]=TX_EN, [1]=RX_EN | Enable transmitter / receiver     |
| 0x4    | UART_TXDATA | W      | [7:0]     | Byte to transmit                          |
| 0x8    | UART_RXDATA | R      | [7:0]     | Byte received                             |
| 0xC    | UART_STATUS | R      | [0]=TX_BUSY, [1]=RX_VALID, [2]=FRAME_ERR | Status flags |

## 6. Config SRAM Layout (Base = 0x2000_0000)

| Offset | Name              | Description                                  |
|--------|-------------------|-----------------------------------------------|
| 0x00   | PROFILE_TEMP_LOW  | Temperature threshold (low), 8-bit           |
| 0x04   | PROFILE_DUTY_LOW  | Duty cycle for low threshold, 8-bit          |
| 0x08   | PROFILE_TEMP_HIGH | Temperature threshold (high), 8-bit          |
| 0x0C   | PROFILE_DUTY_HIGH | Duty cycle for high threshold, 8-bit         |
| 0x10   | PROFILE_ID        | Fan/profile identifier (loaded via SPI)      |

## 7. Error / Status Reporting Convention

- Every peripheral exposes a STATUS register with an ERROR/FAULT bit.
- Bus-level errors (unmapped address, misaligned access) are reported
  via a dedicated `bus_error` signal from the decoder back to the core,
  which the core stores in a memory-mapped diagnostic register
  (not detailed further, treated as a stretch feature).
