### bash - UNIX-based system (Linux, MacOS)
`Open help menu : `
`./report-generator.sh -h`

**Commands**

`./report-generator.sh <project-directory> <username> <from-date> [to-date]`

**Example**

`./report-generator.sh /Users/jonedoe/dev/web-app jonedoe 2025-01-01`

`./report-generator.sh /Users/jonedoe/dev/web-app jonedoe 2025-01-01 2025-12-31`

**Note** : Date format in `YYYY-MM-DD`

### Windows Powershell
`Open help menu : `
`Get-Help .\report-generator.ps1`

**Commands**

`report-generator.ps1 [-ProjectDirectory] <string> [-Username] <string> [-FromDate] <string> [[-ToDate] <string>] [<CommonParameters>]`

**Example**

`.\report-generator.ps1 D:\dev\web-app jonedoe 2025-01-01`

`.\report-generator.ps1 D:\dev\web-app jonedoe 2025-01-01 2025-12-31`

**Note** : Date format in `YYYY-MM-DD`
