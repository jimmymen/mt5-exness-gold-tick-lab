@echo off
"C:\Tools\Python312\python.exe" "C:\QuantResearch\mt5-gold-research\tools\process_exness_tick_archives.py" --output "C:\QuantResearch\tick-data\exness\XAUUSDm" --years 2024 2025 2026 1>"C:\QuantResearch\tick-data\exness\XAUUSDm\processor.stdout.log" 2>"C:\QuantResearch\tick-data\exness\XAUUSDm\processor.stderr.log"
