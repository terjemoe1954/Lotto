# Lotto

A simple SwiftUI app for registering lottery rows, storing draws, and viewing stats/predictions.

## Features
- Register your own rows (7 numbers) with date.
- Register winning rows (8 numbers) with week number.
- List views for both rows and draws with delete actions.
- Statistics: frequency, average interval, and next expected date.
- Prediction: suggests numbers based on historical intervals and a selected date.
- Print/PDF reports with headers and page numbers.

## Data and storage
- Uses SwiftData to store `JackPot` and `Result`.
- On first launch, loads `lotto.json` into the database if it is empty.

## Printing
- Reports render as multiple pages when needed.
- Each page has a header (title + date) and footer with page numbers.

## Settings
- Dark/light mode.
- Prediction tolerance (number of days of deviation).

## Running
1. Open the project in Xcode.
2. Select the scheme and run on simulator/device.

## Notes
- Predictions are statistical and provide no guarantee of winning.
