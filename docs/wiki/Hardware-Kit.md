# PSGadget Hardware Kit and Shopping List

This document lists every component needed to run PSGadget and its reference
examples. Three tiers are provided:

- **Tier 1 - Minimum Starter**: one FT232H, basic passive components, blink an LED.
- **Tier 2 - Full Examples Kit**: everything to run all bundled examples.
- **Tools and Workshop Supplies**: soldering station, test equipment, wire tools, consumables (shared; bought once).
- **Classroom Pack**: per-student breakdown for 10-student groups.

All prices are realistic US retail / Amazon estimates for early 2026. Prices from
Waveshare and Pine64 direct are cheaper but add 2-3 weeks shipping from overseas.
Budget an additional 10-15% above listed prices for shipping, tax, and order minimums.

---

## Table of Contents

- [Sourcing Notes](#sourcing-notes)
- [Chip Capability Quick Reference](#chip-capability-quick-reference)
- [Tier 1 -- Minimum Starter Kit](#tier-1---minimum-starter-kit)
- [Tier 2 -- Full Examples Kit](#tier-2---full-examples-kit)
  - [FTDI Adapters](#ftdi-adapters)
  - [Microcontroller Boards](#microcontroller-boards-micropython--esp-now)
  - [Display](#display)
  - [Passive Components](#passive-components)
- [Tools and Workshop Supplies](#tools-and-workshop-supplies)
  - [Soldering Iron](#soldering-iron)
  - [Solder and Consumables](#solder-and-consumables)
  - [Fume Extraction](#fume-extraction)
  - [Measurement -- Multimeter](#measurement---multimeter)
  - [Hand Tools](#hand-tools)
  - [Workbench](#workbench)
- [Classroom Pack -- Per-Student Cost (10 Students)](#classroom-pack---per-student-cost-10-students)
  - [Per-student components](#per-student-components-individual-bag)
  - [Shared lab components](#shared-lab-components-one-set-per-room-shared-by-all-10-students)
- [Budget Substitutions](#budget-substitutions)
- [Where to Buy -- Quick Links](#where-to-buy---quick-links)
- [Notes on Cables](#notes-on-cables)
- [FTDI Driver (Windows Only)](#ftdi-driver-windows-only)

---

## Sourcing Notes

**Buy genuine FTDI chips.** Counterfeit FTDI ICs are common on Amazon from no-name
resellers. Fake chips perform erratically and are blocked by official FTDI Windows
drivers (older CDM drivers zero-PID the device on plug-in). Reliable sources:

| Supplier | Notes |
|---|---|
| Adafruit (adafruit.com) | Ships genuine chips; good documentation; flat $7 shipping on small orders |
| DigiKey (digikey.com) | Adafruit products stocked here; faster domestic shipping; invoice-friendly for schools |
| Waveshare (waveshare.com) | Genuine FT232R/FT232RNL boards; ships from China (2-3 weeks) or via Amazon storefront at slight markup |
| SparkFun (sparkfun.com) | Genuine boards; good return policy |

Avoid no-name Amazon listings for FTDI boards. If a "FTDI FT232H" board is priced
under $5 it is likely a clone chip.

---

## Chip Capability Quick Reference

| Chip | GPIO method | SPI / I2C | UART | Notes |
|---|---|---|---|---|
| FT232H | ACBUS0-7 via MPSSE | Yes | Yes | Best for I2C displays, SPI sensors, JTAG |
| FT232R / FT232RL | CBUS0-3 bit-bang | No | Yes | 4 GPIO pins; simpler; good for LED / motor |
| FT232RNL | Same as FT232R | No | Yes | RNL is the lead-free variant; functionally identical |

---

## Tier 1 -- Minimum Starter Kit

Covers: module import, `List-PsGadgetFtdi`, `Set-PsGadgetGpio`, LED blink.

| # | Part | Source | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|---|
| 1 | FT232H USB breakout (Adafruit #2264) | Adafruit / DigiKey | $15.00 | 1 | $15.00 | |
| 2 | USB-C cable, data-capable, 3ft | Amazon | $9.00 | 1 | $9.00 | Adafruit #2264 current revision uses USB-C |
| 3 | Half-size solderless breadboard | Amazon | $8.00 | 1 | $8.00 | Name-brand (Elegoo, Adafruit) holds wires better than no-name |
| 4 | Jumper wire kit, M-M + M-F, 120-piece assortment | Amazon | $10.00 | 1 | $10.00 | |
| 5 | LED assorted 5mm 100-pack (red, green, yellow, blue) | Amazon | $8.00 | 1 | $8.00 | 100-pack is better value; you will burn a few |
| 6 | Resistor assortment kit, 10 values x 20pcs (includes 330, 1k, 10k ohm) | Amazon | $10.00 | 1 | $10.00 | |

**Tier 1 estimated total: ~$60**

Covers examples:
- [beginner/Example-BlinkLed.md](../examples/beginner/Example-BlinkLed.md)
- [Getting Started FT232H section](Getting-Started.md)

---

## Tier 2 -- Full Examples Kit

Builds on Tier 1. Adds everything needed to run every bundled example including
bi-color LED, motor control, SSD1306 OLED display, and ESP-NOW wireless telemetry.

### FTDI Adapters

| # | Part | Source | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|---|
| 1 | FT232H USB breakout (Adafruit #2264) | Adafruit / DigiKey | $15.00 | 1 | $15.00 | MPSSE: I2C, SPI, ACBUS GPIO |
| 2 | USB-C cable, data-capable | Amazon | $9.00 | 1 | $9.00 | For Adafruit #2264 |
| 3 | FT232R USB UART Type-C (Waveshare) | waveshare.com / Amazon | $9.00 | 1 | $9.00 | CBUS GPIO; on-board voltage jumper 3.3V/5V; classroom-friendly |
| 4 | USB-C cable, data-capable, 3ft | Amazon | $9.00 | 1 | $9.00 | For Waveshare FT232R |

### Microcontroller Boards (MicroPython / ESP-NOW)

| # | Part | Source | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|---|
| 5 | ESP32-S3 Mini (Waveshare) | waveshare.com / Amazon | $12.00 | 2 | $24.00 | ESP-NOW receiver + transmitter; dual-core; Bluetooth 5 |
| 6 | USB-C cable, data-capable | Amazon | $9.00 | 2 | $18.00 | One per ESP32; needed for flashing MicroPython |

One board acts as ESP-NOW receiver (wired to FT232H UART), one as transmitter
(battery or USB). Substitute ESP32-C3 Mini (~$7) for cost reduction; single-core
RISC-V but fully compatible.

### Display

| # | Part | Source | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|---|
| 7 | SSD1306 128x64 OLED, I2C, 0.96" | Amazon | $9.00 | 1 | $9.00 | Verify silkscreen pin order (VCC/GND varies by board); I2C addr 0x3C default |

### Passive Components

| # | Part | Source | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|---|
| 8 | Half-size breadboard | Amazon | $8.00 | 3 | $24.00 | One per active sub-circuit; reusable |
| 9 | Jumper wire kit M-M + M-F 120-piece | Amazon | $10.00 | 1 | $10.00 | |
| 10 | Solid core hookup wire 22 AWG, 6-color, 30ft each (TUOFENG or equiv.) | Amazon | $18.00 | 1 | $18.00 | Cut-to-length breadboard runs and permanent wiring |
| 11 | Header pins, breakaway 40-pin, straight male, 10-strip pack | Amazon | $10.00 | 1 | $10.00 | Solder onto bare castellated modules |
| 12 | Header pins, breakaway 40-pin, female, 5-strip pack | Amazon | $10.00 | 1 | $10.00 | Socket connectors; lets modules be swapped without resoldering |
| 13 | Resistor assortment kit, 10 values x 20pcs | Amazon | $10.00 | 1 | $10.00 | |
| 14 | LED assorted 5mm 100-pack | Amazon | $8.00 | 1 | $8.00 | |
| 15 | Bi-color LED, common-cathode, 3-leg, red+green, 5-pack | Amazon | $6.00 | 1 | $6.00 | Verify middle leg = cathode; test with a coin cell before wiring |
| 16 | NPN transistor 2N2222 or BC547, 50-pack | Amazon | $8.00 | 1 | $8.00 | Motor driver; also useful as general-purpose switches |
| 17 | Small DC motor, 3-6V, 130-size | Amazon | $10.00 | 1 | $10.00 | 2-pack usually same price as single |
| 18 | Heat shrink tubing assortment, 2:1, 6 sizes | Amazon | $10.00 | 1 | $10.00 | Insulate soldered joints |
| 19 | Small parts organizer, 24-compartment | Amazon | $14.00 | 1 | $14.00 | Keep resistors, LEDs, transistors sorted; saves significant time |

**Tier 2 full kit estimated total (Tier 1 + Tier 2): ~$240**

Covers all bundled examples:

| Example | FTDI board | Additional parts used |
|---|---|---|
| [beginner/Example-BlinkLed.md](../examples/beginner/Example-BlinkLed.md) | FT232H | LED, 330 ohm resistor |
| [Example-BicolorLed.md](../examples/Example-BicolorLed.md) | FT232R | bi-color LED, 2x 1k resistors |
| [Example-Ft232rMotor.md](../examples/Example-Ft232rMotor.md) | FT232R | NPN transistor, 1k resistor, DC motor |
| [Example-Ssd1306.md](../examples/Example-Ssd1306.md) | FT232H | SSD1306 OLED, 4 jumper wires |
| [Example-EspNow.md](../examples/Example-EspNow.md) | FT232H | 2x ESP32-S3, USB-C cables, 4 jumper wires |

---

## Tools and Workshop Supplies

These are bought once and shared across projects. Only solder, flux, and filter
cartridges are consumed. Do not skip the multimeter or fume extractor.

### Soldering Iron

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 1 | PINECIL Smart Mini Portable Soldering Iron (Pine64 or Amazon) | $35.00 | 1 | $35.00 | USB-C PD powered; temperature-controlled; TS100-compatible tips; heats in under 10 seconds |
| 2 | Extra tips: 6-piece TS100/TS101/Pinecil V2 kit (TS-C4, TS-K, TS-ILS, TS-J02, TS-D24) with threaded insert adapter | $22.00 | 1 | $22.00 | TS-C4 chisel and TS-K knife see the most use; ILS/J02 for fine SMD work |
| 3 | USB-C PD power supply, 65W minimum | $22.00 | 1 | $22.00 | Pinecil requires USB-C PD to reach soldering temps; a modern laptop charger often works |

**Pinecil iron + tips: ~$80 total** (matches the $80 budget)

The Pinecil is strongly preferred over cheap fixed-temperature irons. It is travel-sized,
boots instantly, auto-sleeps on inactivity, and runs off the same USB-C charger as your
laptop. For a classroom, budget one iron per 2-3 students.

### Solder and Consumables

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 4 | Lead-free solder, SAC305 or no-lead 63/37, 0.8mm / 0.031", 100g spool | $16.00 | 1 | $16.00 | 0.8mm is easier to control than 1.0mm; avoid leaded solder in classrooms |
| 5 | Flux pen, no-clean rosin | $12.00 | 1 | $12.00 | Apply before rework; wicks solder; prevents cold joints |
| 6 | Brass wire tip cleaner with weighted holder | $10.00 | 1 | $10.00 | Dry cleaning extends tip life far longer than a wet sponge |
| 7 | Isopropyl alcohol 99%, 16oz | $12.00 | 1 | $12.00 | Flux residue cleanup after soldering; also cleans boards and connectors |

### Fume Extraction

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 8 | Solder fume extractor fan with activated carbon filter, 3-speed | $50.00 | 1 | $50.00 | Position 4-6" from workpiece; replace carbon filter every 15-20 hours of use |
| 9 | Replacement carbon filter cartridges, 3-pack | $15.00 | 1 | $15.00 | Buy spares at purchase time; filters are model-specific |

Lead-free solder still produces irritating and harmful flux fumes. A fume extractor is
not optional for any regular use or classroom environment.

### Measurement -- Multimeter

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 10 | Digital multimeter, auto-ranging, with continuity buzzer (AstroAI AM33D, KAIWEETS HT118A, or equiv.) | $35.00 | 1 | $35.00 | Continuity mode essential for debugging wiring; measures DC voltage, resistance, diode |
| 11 | Test lead set with alligator clips, 10-piece | $12.00 | 1 | $12.00 | Hands-free probing; clip to rails while the circuit runs |

The multimeter is the single most important debugging tool on the bench. Use it to:
- Verify 3.3V / 5V rail is present before connecting a board
- Confirm GPIO pin voltage (HIGH/LOW) matches what PSGadget reports
- Check continuity of a wire before blaming the code
- Identify polarity on unmarked components

For a classroom, buy one multimeter per workbench (2-3 students).

### Hand Tools

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 12 | Wire stripper / cutter, adjustable 20-30 AWG | $18.00 | 1 | $18.00 | Adjustable notch prevents nicking the conductor; do not use scissors or a knife |
| 13 | Flush-cut micro wire cutters | $14.00 | 1 | $14.00 | Trim component leads flush after soldering; also cut hookup wire to length |
| 14 | Needle-nose pliers, 5" | $12.00 | 1 | $12.00 | Bend component leads, hold header pins during soldering, retrieve dropped parts |
| 15 | Reverse-action tweezers (releases when squeezed) | $10.00 | 1 | $10.00 | Hold small SMD parts and header pins in place while soldering |
| 16 | Helping hands / third-hand tool with alligator clips | $20.00 | 1 | $20.00 | Holds PCB while both hands hold the iron and solder |

### Workbench

| # | Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|---|
| 17 | ESD / anti-static silicone mat, 12x16" | $22.00 | 1 | $22.00 | Protects boards from static; heat-resistant surface for brief iron rests |
| 18 | USB hub, 7-port powered | $28.00 | 1 | $28.00 | Necessary when FT232H + FT232R + 2x ESP32 are connected simultaneously; unpowered hubs drop devices |

**Tools section estimated total (one-time, shared): ~$390**

For a classroom of 10 students: plan one iron, one multimeter, one fume extractor,
and one set of cutting tools per workbench (2-3 students per bench).

---

## Classroom Pack -- Per-Student Cost (10 Students)

Recommended configuration: each student gets their own FT232H + FT232R + basics.
ESP32 boards shared in pairs (ESP-NOW already needs two boards per pair).

### Per-student components (individual bag)

| Part | Unit Price | Qty | Per-Student |
|---|---|---|---|
| FT232H USB breakout (Adafruit #2264) | $15.00 | 1 | $15.00 |
| USB-C cable (for FT232H) | $9.00 | 1 | $9.00 |
| FT232R USB UART Type-C (Waveshare) | $9.00 | 1 | $9.00 |
| USB-C cable | $9.00 | 1 | $9.00 |
| Half-size breadboard x3 | $8.00 | 3 | $24.00 |
| Jumper wire kit 120-piece | $10.00 | 1 | $10.00 |
| Solid core hookup wire 22 AWG 6-color | $18.00 | 1 | $18.00 |
| Header pins M breakaway strip | $10.00 | 1 | $10.00 |
| Header pins F breakaway strip | $10.00 | 1 | $10.00 |
| Resistor assortment kit | $10.00 | 1 | $10.00 |
| LED assorted 100-pack | $8.00 | 1 | $8.00 |
| Bi-color LED 3-leg 5-pack | $6.00 | 1 | $6.00 |
| NPN transistor 2N2222 50-pack | $8.00 | 1 | $8.00 |
| DC motor 130-size | $10.00 | 1 | $10.00 |
| SSD1306 OLED 0.96" I2C | $9.00 | 1 | $9.00 |
| Heat shrink tubing assortment | $10.00 | 1 | $10.00 |
| Component organizer box | $14.00 | 1 | $14.00 |
| **Per-student subtotal** | | | **~$179** |

### Shared lab components (one set per room, shared by all 10 students)

| Part | Unit Price | Qty | Total | Notes |
|---|---|---|---|---|
| ESP32-S3 Mini (Waveshare) | $12.00 | 10 | $120.00 | One per student; 2 needed per ESP-NOW pair |
| USB-C cable for ESP32 flashing | $9.00 | 5 | $45.00 | |
| PINECIL soldering iron | $35.00 | 3 | $105.00 | One per workbench |
| Pinecil 6-tip kit | $22.00 | 3 | $66.00 | |
| USB-C 65W PD supply for Pinecil | $22.00 | 3 | $66.00 | |
| Lead-free solder 100g spool | $16.00 | 3 | $48.00 | |
| Flux pen no-clean | $12.00 | 3 | $36.00 | |
| Brass tip cleaner | $10.00 | 3 | $30.00 | |
| Isopropyl alcohol 99% 16oz | $12.00 | 2 | $24.00 | |
| Solder fume extractor | $50.00 | 2 | $100.00 | One per 1-2 workbenches |
| Replacement carbon filter 3-pack | $15.00 | 2 | $30.00 | |
| Digital multimeter | $35.00 | 3 | $105.00 | One per workbench |
| Test lead set with alligator clips | $12.00 | 3 | $36.00 | |
| Wire stripper / cutter | $18.00 | 3 | $54.00 | |
| Flush-cut micro cutters | $14.00 | 3 | $42.00 | |
| Needle-nose pliers | $12.00 | 3 | $36.00 | |
| Reverse-action tweezers | $10.00 | 3 | $30.00 | |
| Helping hands | $20.00 | 3 | $60.00 | |
| ESD anti-static mat | $22.00 | 3 | $66.00 | |
| USB hub 7-port powered | $28.00 | 3 | $84.00 | |
| **Shared subtotal** | | | **~$1,183** | |

**10-student classroom total (electronics + tools): ~$2,973**
**Per-student all-in (tools amortized): ~$297**
**Per-student electronics only (no tools): ~$191**

The tools are a one-time purchase. Amortized over three cohorts of 10 students, the
per-student tool cost drops to approximately $40.

---

## Budget Substitutions

| Substitution | Savings per unit | Trade-off |
|---|---|---|
| Replace ESP32-S3 Mini ($12) with ESP32-C3 Mini ($7) | $5.00 | Single-core RISC-V; ESP-NOW still works; Bluetooth 5 present |
| Replace Pinecil ($35) with TS100 iron ($55-70) | -$20 | TS100 needs barrel plug PSU; heavier; Pinecil is better value |
| Replace AstroAI multimeter ($35) with Fluke 101 ($70) | -$35 | Fluke is more durable and accurate; worth it for a permanent lab |
| Order FTDI boards direct from Waveshare vs Amazon | $3-5/board | 2-3 week lead time; fine for planned purchases |
| Buy resistor/LED components on AliExpress in bulk | $20-30/class | 4-6 week lead; acceptable for planned course prep |
| Skip component organizer boxes; use zip-loc bags | $14/student | Components get mixed and lost quickly |

---

## Where to Buy -- Quick Links

| Item | Suggested Link |
|---|---|
| Adafruit FT232H #2264 | https://www.adafruit.com/product/2264 |
| DigiKey FT232H (Adafruit #2264) | https://www.digikey.com/en/products/detail/adafruit-industries-llc/2264/5761217 |
| Waveshare FT232 USB UART Type-C | https://www.waveshare.com/ft232-usb-uart-board-type-c.htm |
| Waveshare usb_to_ttl_ft232 compact | https://www.waveshare.com/usb-to-ttl-ft232.htm |
| Waveshare ESP32-S3 Mini | https://www.waveshare.com/catalogsearch/result/index/?mode=list&q=esp32+zero |
| Waveshare ESP32-C3 Mini | https://www.waveshare.com/catalogsearch/result/index/?mode=list&q=esp32+zero |
| PINECIL Smart Soldering Iron | https://pine64.com/product/pinecil-smart-mini-portable-soldering-iron/ |
| TS100/Pinecil compatible tip kit (6pcs) | Search: "TS100 6PCS soldering tips threaded insert adapter Pinecil" on Amazon |
| TUOFENG 22 AWG solid core wire 6-color | Search: "TUOFENG 22 AWG solid hookup wire breadboard" on Amazon |

All prices approximate as of early 2026. Verify current pricing before ordering.

---

## Notes on Cables

- **Adafruit FT232H #2264 uses USB-C** on the current board revision. A standard
  USB-C data cable works. Charge-only USB-C cables have no data lines and will not
  be detected -- use a cable rated for data (2A+ recommended).
- Waveshare FT232R boards and ESP32 boards use USB-C. Any standard USB-C data cable
  at 2A+ works. Avoid thin "charging-only" USB-C cables.
- Use a **powered USB hub** when connecting three or more FTDI / ESP32 devices
  simultaneously. Bus-powered hubs from laptop USB-A ports often drop devices under load.

---

## FTDI Driver (Windows Only)

The D2XX driver must be installed on Windows for hardware access. Linux and macOS
use `libftd2xx.so` / `libftd2xx.dylib`. See [Getting-Started](Getting-Started.md) for installation instructions
driver installation steps by platform and persona.
