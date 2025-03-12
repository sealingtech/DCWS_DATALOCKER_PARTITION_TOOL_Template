# DCWS Datalocker Partitioning Tool

## 📌 Overview
The **DCWS Datalocker Partitioning Tool** is designed to format and configure a bootable USB drive for **DCWS deployments**. It partitions the USB drive, installs **GRUB**, and prepares it for use with **HAT, SHB_Deploy, and DCWS_Deploy**.

## 🚀 Features
- **Automated partitioning and formatting**
- **GRUB bootloader installation**
- **HAT-OFFLINE setup for hardware acceptance testing**
- **Prepares partitions for SHB_Deploy and DCWS_Deploy**
- **Creates a system log for tracking operations**

---

## 📂 Directory Structure
This tool consists of the following files and folders:

````graphql
DCWS_Datalocker_Partition_Tool/
│── DCWS_Deploy/                  # Storage for DCWS deployment files (User must manually add files)
│── SHB_Deploy/                   # Storage for SHB deployment files (User must manually add files)
│── grub-2.06-for-windows/        # GRUB bootloader files
│── signed-grub-files/            # Signed GRUB EFI boot files
│── HAT-OFFLINE-dev20250210.iso   # Hardware Acceptance Tool (HAT) ISO (Mounted & Copied Automatically)
│── DCWS_USB_Setup.ps1            # PowerShell script to partition, format, and set up the USB
│── README.md                     # Documentation (this file)
│── README.pdf                    # PDF version of documentation

````

### **📌 Notes**
- **DCWS_Deploy & SHB_Deploy** are empty by default. The user must manually **import** deployment files before use.
- **HAT-OFFLINE-dev20250210.iso** is automatically mounted and copied by the script.
- **GRUB files** are required for booting—do not delete them.
- The **PowerShell script** (`DCWS_USB_Setup.ps1`) handles the full partitioning and setup process.


## 📂 USB Partition Layout
| **Partition**    | **Label**        | **File System** | **Size**  | **Purpose** |
|-----------------|-----------------|---------------|----------|-------------|
| `SHB_Boot`      | `SHB_BOOT`       | `FAT32`       | `3GB`    | Bootloader partition (GRUB) |
| `SHB_Deploy`    | `SHB_DEPLOY`     | `NTFS`        | `35GB`   | Storage for SHB deployment files |
| `HAT`           | `HAT-OFFLINE`    | `FAT32`       | `6GB`    | Hardware Acceptance Tool (HAT) |
| `DCWS_Deploy`   | `DCWS_DEPLOY`    | `NTFS`        | `Remaining Space` | Storage for DCWS deployment files |

---

## 🛠️ How to Use the Tool

### **Step 1: Manually Import SHB_Deploy and DCWS_Deploy Files**
- The **SHB_Deploy** and **DCWS_Deploy** partitions will be empty by default.
- Users must manually **import the deployment files** to these partitions.
- Simply **copy your files** into:
- **SHB_Deploy (H:)** → Store **SHB deployment files**.
- **DCWS_Deploy (I:)** → Store **DCWS deployment files**.
- Import the HAT ISO into the directory that you will be running the script from. 

### **Step 2: Run the Partitioning Script**
1. Insert the **USB drive** into your computer.
2. Open **PowerShell as Administrator**.
3. Navigate to the tool’s folder:
````powershell
cd "C:\Path\To\DCWS_Datalocker_Partition_Tool"
````
4. Run the script:
````powershell
.\DCWS_USB_Setup.ps1
````
5. Select the disk number **(WARNING: This will erase all data on the selected disk!)**.

### **Step 3: Verify the USB Drive**
After the script completes:
- The USB should contain **SHB_Boot, HAT-OFFLINE, SHB_Deploy, and DCWS_Deploy** partitions.
- The **log file (`DCWS_USB_Setup.log`)** will be available on the local machine in the folder where the deployment script was run from.
---

## 📜 System Log
The script logs all actions in:
- **Local machine** → `DCWS_USB_Setup.log`

Use this log to debug any issues.
---

## ⚠️ **Warnings**
- **Import SHB_Deploy and DCWS_Deploy files manually before setup.**
- **All data on the selected USB drive will be erased.**
- **Ensure you have the correct disk number before running the script.**
---

## 📝 Notes
- This tool was developed by **James A. Muldrow** for the **SealingTech DCWS Program**.
- For support, contact the **DCWS engineering team**.

## 🛠️ Modifying GRUB Boot Entries
If you need to update the GRUB boot menu, modify **`grub.cfg`** on the `SHB_Boot` partition.

Example `grub.cfg`:
````cfg
set timeout=5 set default=0

menuentry "Boot SealingTech Hardware Acceptance Tool (HAT) (J: FAT)" { 
    insmod part_gpt 
    insmod fat 
    search --no-floppy --set=root --label "HAT-OFFLINE" 
    chainloader /efi/boot/bootx64.efi 
}

menuentry "Boot SHB_Deploy (H: NTFS)" { 
    insmod part_gpt 
    insmod ntfs search 
    --no-floppy --set=root 
    --label "SHB_Deploy" 
    chainloader /EFI/Boot/bootx64
}
````

## 📢 Support
For any issues, please contact the **DCWS Engineering Team**.


