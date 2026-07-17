@echo off
"C:\Tools\Python312\python.exe" "C:\QuantResearch\mt5-gold-research\tools\download_exness_monthly_archives.py" --output "C:\QuantResearch\tick-data\exness\XAUUSDm\monthly" --start-year 2021 --workers 4 1>"C:\QuantResearch\tick-data\exness\XAUUSDm\monthly.stdout.log" 2>"C:\QuantResearch\tick-data\exness\XAUUSDm\monthly.stderr.log"
