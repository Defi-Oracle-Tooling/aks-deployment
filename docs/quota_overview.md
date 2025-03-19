# Quota Overview

## Overview
The quota overview provides information on the maximum vCPUs and optimal VM sizes for different regions.

## Quota Details
| **Region** | **Max vCPUs**    | **Optimal VM** | **Node Count** |
|------------|------------------|----------------|----------------|
| 108        | Standard_D16s_v4 | 6              |
| 32         | Standard_D4s_v4  | 7              |
| 24         | Standard_D4s_v4  | 5              |
| 10         | Standard_D2s_v4  | 4              |

![Quota Overview](images/quota_overview.png)

## Notes
- The recommended instance type is Standard D16S_v5, with an upgrade path to D32S_v5 and then D64S_v5.
- More optimal choices with better memory options include the FS_v2 and E_v2 VMs.
- The DS_v4 series was chosen as the starting point due to a balance of total enabled regions and system requirements.
