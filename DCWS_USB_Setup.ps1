# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as an Administrator!" -ForegroundColor Red
    exit
}

# Get the directory where the script is located
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define Log File Path
$LogFilePath = Join-Path -Path $ScriptDirectory -ChildPath "DCWS_USB_Setup.log"

# Start Logging the entire script execution
Start-Transcript -Path $LogFilePath -Append -NoClobber

# Function to Print a Clean DCWS Banner
function Show-DCWSBanner {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "       DCWS Bootable USB Setup Script       " -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Author  : James A. Muldrow" -ForegroundColor Green
    Write-Host "Version : 1.0" -ForegroundColor Green
    Write-Host "Date    : $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Green
    Write-Host "---------------------------------------------" -ForegroundColor Cyan
    Write-Host "This script sets up a bootable USB with GRUB." -ForegroundColor Yellow
    Write-Host "Partitions will be created and formatted." -ForegroundColor Yellow
    Write-Host "This drive is formatted and partitioned" -ForegroundColor Magenta
    Write-Host "specifically for DCWS deployment drives." -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Cyan
}

# Call the function at the beginning of the script
Show-DCWSBanner

# Open Disk Management 
diskmgmt.msc

# Set GRUB Install Path to always be in the same directory as the script
$GrubInstallPath = Join-Path -Path $ScriptDirectory -ChildPath "grub-2.06-for-windows"

# Set the path to the signed GRUB files dynamically
$SignedGrubPath = Join-Path -Path $ScriptDirectory -ChildPath "signed-grub-files"

# Define source file paths
$ShimSource = Join-Path -Path "$SignedGrubPath" -ChildPath "BOOTX64.EFI"
$GrubSource = Join-Path -Path "$SignedGrubPath" -ChildPath "grubx64.efi"

# Confirm the path exists
if (-not (Test-Path $GrubInstallPath)) {
    Write-Host "ERROR: GRUB install folder not found at $GrubInstallPath" -ForegroundColor Red
    Stop-Transcript
    exit
}

# Confirm the path exists
if (-not (Test-Path $SignedGrubPath)) {
    Write-Host "ERROR: Signed GRUB files folder not found at $SignedGrubPath" -ForegroundColor Red
    Stop-Transcript
    exit
}

# Define partition sizes (in MB)
$BootPartitionSize = 3000
$DeployPartitionSize = 35000
$HatPartitionSize = 6000

# Define drive letters
$BootLetter = "G"
$DeployLetter = "H"
$DCWSLetter = "I"
$HatLetter = "J"

# Destination partitions
$HATDest = "J:\"          # HAT partition
$SHBDeployDest = "H:\"    # SHB_Deploy partition
$DCWSDeployDest = "I:\"   # DCWS_Deploy partition

do {

    # List available disks
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Available Disks:" -ForegroundColor Cyan
    Get-Disk | Select-Object Number, FriendlyName, @{Name="Size(GB)";Expression={[math]::Round($_.Size / 1GB, 2)}}, PartitionStyle | Format-Table -AutoSize

    # Prompt user to select the correct disk
    $DiskNumber = Read-Host "Enter the disk number to format (or type 'EXIT' to cancel)"

    # Check if the user wants to exit
    if ($DiskNumber -eq "EXIT") {
        Write-Host "Exiting script. No changes were made." -ForegroundColor Yellow
        Stop-Transcript
        exit
    }

    # Validate disk selection
    $Disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    if (-not $Disk) {
        Clear-Host  # Clears the screen for a clean prompt
        Write-Host "Invalid disk selection. No disk found with number $DiskNumber. Try again." -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }

    # Check if the disk has existing partitions
    $ExistingPartitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue

    if ($ExistingPartitions) {
        # Check if C: is present on this disk
        $ContainsCDrive = $ExistingPartitions | Get-Volume | Where-Object { $_.DriveLetter -eq "C" }

        if ($ContainsCDrive) {
            Clear-Host  # Clears the screen for a clean prompt
            Write-Host "ERROR: You selected the disk containing the Windows OS (C). This operation is not allowed!" -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }
    } else {
        Write-Host "WARNING: Disk $DiskNumber is empty and has no partitions. Proceeding with partitioning." -ForegroundColor Yellow
    }

    Write-Host "Disk $DiskNumber selected successfully and does not contain C:\." -ForegroundColor Green

    # Confirm before proceeding
    $Confirm = Read-Host "Are you sure you want to erase and partition Disk $DiskNumber? Type 'YES' to confirm (or 'EXIT' to cancel)"
    if ($Confirm -eq "EXIT") {
        Write-Host "Exiting script. No changes were made." -ForegroundColor Yellow
        Stop-Transcript
        exit
    }

    if ($Confirm -ne "YES") {
        Write-Host "Operation canceled. Please select a valid disk again." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue
    }

    # If we reach this point, the selection is valid, and the loop will exit
    break

} while ($true)  # Loop continues until valid input is provided

# Clear the disk so we initialize it fresh
Write-Host "Cleaning Disk $DiskNumber..."
Clear-Disk -Number $DiskNumber -RemoveData  -Confirm:$false

# Ensure the disk is initialized
$Disk = Get-Disk -Number $DiskNumber
if ($Disk.PartitionStyle -eq "RAW" -or $Disk.PartitionStyle -eq "MBR") 
{
    
    if ($Disk.PartitionStyle -eq "MBR")
    {
        Write-Host "Disk $DiskNumber is currently MBR. Converting it to GPT..." -ForegroundColor Yellow
        Set-Disk -Number $DiskNumber -PartitionStyle GPT  # Convert the disk to GPT
    } else {

        Write-Host "Disk $DiskNumber is uninitialized. Initializing it as GPT..." -ForegroundColor Yellow
        Initialize-Disk -Number $DiskNumber -PartitionStyle GPT
    }

    Start-Sleep -Seconds 2  # Initial wait
    
    # Force Windows to refresh disk state
    Write-Host "Forcing Windows to refresh the disk state..." -ForegroundColor Yellow
    Update-HostStorageCache
    Start-Sleep -Seconds 2  

    # Wait until the disk is recognized as GPT
    $MaxAttempts = 10
    $Attempts = 0
    do {
        Start-Sleep -Seconds 1
        $Disk = Get-Disk -Number $DiskNumber
        $Attempts++
        if ($Attempts -ge $MaxAttempts) {
            Write-Host "ERROR: Disk initialization took too long. Exiting..." -ForegroundColor Red
            Stop-Transcript
            exit
        }
    } while ($Disk.PartitionStyle -eq "RAW")

    Write-Host "Disk $DiskNumber is now fully initialized as GPT." -ForegroundColor Green
}

# Re-check the disk to confirm initialization before partitioning
$Disk = Get-Disk -Number $DiskNumber
if ($Disk.PartitionStyle -ne "GPT") {
    Write-Host "ERROR: Disk $DiskNumber did not initialize properly. Exiting..." -ForegroundColor Red
    Stop-Transcript
    exit
}

Write-Host "Disk $DiskNumber is confirmed as GPT. Proceeding with partitioning..." -ForegroundColor Green


# Create Partitions with Assigned Drive Letters
Write-Host "Creating partitions on Disk $DiskNumber..."
$BootPartition = New-Partition -DiskNumber $DiskNumber -Size ($BootPartitionSize * 1MB) -DriveLetter $BootLetter
$DeployPartition = New-Partition -DiskNumber $DiskNumber -Size ($DeployPartitionSize * 1MB) -DriveLetter $DeployLetter
$HatPartition = New-Partition -DiskNumber $DiskNumber -Size ($HatPartitionSize * 1MB) -DriveLetter $HatLetter
$DCWSPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter $DCWSLetter

# Format Partitions
Write-Host "Formatting partitions..."
Format-Volume -DriveLetter $BootLetter -FileSystem FAT32 -NewFileSystemLabel "SHB_Boot" -Confirm:$false
Format-Volume -DriveLetter $DeployLetter -FileSystem NTFS -NewFileSystemLabel "SHB_Deploy" -Confirm:$false
Format-Volume -DriveLetter $HatLetter -FileSystem FAT32 -NewFileSystemLabel "HAT-OFFLINE" -Confirm:$false
Format-Volume -DriveLetter $DCWSLetter -FileSystem NTFS -NewFileSystemLabel "DCWS_Deploy" -Confirm:$false

Write-Host "Partitions created successfully with assigned drive letters!" -ForegroundColor Green

# Ensure the Boot Partition exists before proceeding
if (-not $BootPartition -or -not $BootPartition.DriveLetter) {
    Write-Host "ERROR: Boot partition not found. GRUB installation cannot proceed." -ForegroundColor Red
    Stop-Transcript
    exit
}

# Set the Boot Drive Letter
$BootDrive = $BootPartition.DriveLetter + ":"

# Ensure the Boot Drive is formatted correctly
$BootVolume = Get-Volume -DriveLetter $BootPartition.DriveLetter -ErrorAction SilentlyContinue
if (-not $BootVolume -or $BootVolume.FileSystem -ne "FAT32") {
    Write-Host "ERROR: Boot partition is not formatted as FAT32. GRUB installation requires a FAT32 EFI partition." -ForegroundColor Red
    Stop-Transcript
    exit
}

Write-Host "Installing GRUB on $BootDrive..."

# Install GRUB Bootloader (Ensure UEFI Boot)
Start-Process -FilePath "$GrubInstallPath\grub-install.exe" -ArgumentList "--target=x86_64-efi --efi-directory=$BootDrive --boot-directory=$BootDrive\boot --removable" -NoNewWindow -Wait

Write-Host "GRUB Installation complete!" -ForegroundColor Green

# Ensure necessary directories exist before copying GRUB files
$EFIPath = "$BootDrive\EFI"
$BootPath = "$BootDrive\boot"

if (-not (Test-Path $EFIPath)) {
    Write-Host "Creating EFI directory: $EFIPath"
    New-Item -Path $EFIPath -ItemType Directory -Force
}

if (-not (Test-Path $BootPath)) {
    Write-Host "Creating Boot directory: $BootPath"
    New-Item -Path $BootPath -ItemType Directory -Force
}

# Define the correct GRUB source directories
$GrubBootloaderPath = "$GrubInstallPath\x86_64-efi"   # 64-bit UEFI bootloader files
$GrubBIOSPath = "$GrubInstallPath\i386-pc"            # Legacy BIOS bootloader files

# Ensure GRUB Bootloader directory exists before copying
if (Test-Path $GrubBootloaderPath) {
    Write-Host "Copying GRUB UEFI bootloader files..."
    Copy-Item -Path "$GrubBootloaderPath\*" -Destination "$BootPath\" -Recurse -Force
} else {
    Write-Host "WARNING: GRUB UEFI bootloader files not found at $GrubBootloaderPath. Skipping UEFI bootloader copy." -ForegroundColor Yellow
}

if (Test-Path $GrubBIOSPath) {
    Write-Host "Copying GRUB Legacy BIOS bootloader files..."
    Copy-Item -Path "$GrubBIOSPath\*" -Destination "$BootPath\" -Recurse -Force
} else {
    Write-Host "WARNING: GRUB Legacy BIOS bootloader files not found at $GrubBIOSPath. Skipping Legacy BIOS bootloader copy." -ForegroundColor Yellow
}

Write-Host "GRUB bootloader files copied!" -ForegroundColor Green

# Set the path for SHB_Boot grub.cfg
$GrubCfgPath = "$BootPath\grub\grub.cfg"
Write-Host "Creating GRUB configuration file..."

# Write SHB_BOOT grub.cfg
@"
set timeout=5
set default=0

menuentry "Boot SealingTech Hardware Acceptance Tool (HAT) (J: FAT)" {
    insmod part_gpt
    insmod fat
    search --no-floppy --set=root --label "HAT-OFFLINE"
    chainloader /efi/boot/bootx64.efi
}

menuentry "Boot SHB_Deploy (H: NTFS)" {
    insmod part_gpt
    insmod ntfs
    search --no-floppy --set=root --label "SHB_Deploy"
    chainloader /EFI/Boot/bootx64.efi
}
"@ | Out-File -Encoding utf8 -FilePath $GrubCfgPath -Force

Write-Host "SHB_BOOT GRUB configuration file created!" -ForegroundColor Green

# Copy the signed GRUB files to the boot partition
Write-Host "Copying signed GRUB files to USB boot partition..."
Copy-Item -LiteralPath $ShimSource -Destination "$EFIPath\BOOT\BOOTX64.EFI" -Force
Copy-Item -LiteralPath $GrubSource -Destination "$EFIPath\BOOT\grubx64.efi" -Force


Write-Host "Signed GRUB files copied successfully!" -ForegroundColor Green

# Define Paths
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# ISO file for HAT
$HATISO = Join-Path -Path $ScriptDirectory -ChildPath "HAT-OFFLINE-dev20250210.iso"

# Local folders
$SHBDeploySource = Join-Path -Path $ScriptDirectory -ChildPath "SHB_Deploy"
$DCWSDeploySource = Join-Path -Path $ScriptDirectory -ChildPath "DCWS_Deploy"

# Function to Mount ISO
function Mount-ISO {
    param ([string]$ISOPath)
    
    Write-Host "Mounting ISO: $ISOPath" -ForegroundColor Cyan
    $ISO = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 2  # Ensure it's fully mounted

    # Get Drive Letter of the Mounted ISO
    $DriveLetter = ($ISO | Get-Volume).DriveLetter + ":"
    
    if (-not $DriveLetter) {
        Write-Host "ERROR: Unable to mount ISO!" -ForegroundColor Red
        Stop-Transcript
        exit 1
    }

    Write-Host "ISO Mounted at $DriveLetter" -ForegroundColor Green
    return $DriveLetter
}

# Function to Copy Files Using Robocopy
function Copy-FolderContents {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Label
    )

    Write-Host "---------------------------------------------" -ForegroundColor Cyan
    Write-Host "Checking for $Label files to copy..." -ForegroundColor Cyan

    if (-not (Test-Path $SourcePath)) {
        Write-Host "WARNING: $Label source folder not found at $SourcePath! Skipping..." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $DestinationPath)) {
        Write-Host "Creating destination directory: $DestinationPath" -ForegroundColor Cyan
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Copying $Label files using Robocopy..." -ForegroundColor Yellow
    $RobocopyCommand = "robocopy `"$SourcePath`" `"$DestinationPath`" /E /COPY:DAT /R:3 /W:2 /NP /TEE"
    Invoke-Expression $RobocopyCommand

    Write-Host "$Label files copied successfully!" -ForegroundColor Green
    Write-Host "---------------------------------------------" -ForegroundColor Cyan
}

# Start Copying Process
Write-Host "Starting file copy process for deployment drives..." -ForegroundColor Cyan

# Mount the ISO and copy HAT files
$MountedISODrive = Mount-ISO -ISOPath $HATISO
$HATSource = "$MountedISODrive\"
Copy-FolderContents -SourcePath $HATSource -DestinationPath $HATDest -Label "HAT"

# Set the path for HAT grub.cfg
$HATCfgPath = "$HATDest\efi\boot\grub.cfg"
Write-Host "Creating HAT GRUB configuration file..."

# Write HAT grub.cfg
@"
set default="0"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=1
### END /etc/grub.d/00_header ###

search --no-floppy --set=root -l 'HAT-OFFLINE'

### BEGIN /etc/grub.d/10_linux ###
menuentry 'Start HAT-OFFLINE-dev20250210 40' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=HAT-OFFLINE  rd.live.image quiet rhgb
	initrdefi /images/pxeboot/initrd.img
}
menuentry 'Test this media & start HAT-OFFLINE-dev20250210 40' --class fedora --class gnu-linux --class gnu --class os {
	linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=HAT-OFFLINE  rd.live.image rd.live.check quiet
	initrdefi /images/pxeboot/initrd.img
}
submenu 'Troubleshooting -->' {
	menuentry 'Start HAT-OFFLINE-dev20250210 40 in basic graphics mode' --class fedora --class gnu-linux --class gnu --class os {
		linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=HAT-OFFLINE  rd.live.image nomodeset quiet rhgb
		initrdefi /images/pxeboot/initrd.img
	}
}

"@ | Out-File -Encoding utf8 -FilePath $HATCfgPath -Force

Write-Host "HAT GRUB configuration file created!" -ForegroundColor Green

# Copy remaining folders from local storage
Copy-FolderContents -SourcePath $SHBDeploySource -DestinationPath $SHBDeployDest -Label "SHB_Deploy"
Copy-FolderContents -SourcePath $DCWSDeploySource -DestinationPath $DCWSDeployDest -Label "DCWS_Deploy"

# Unmount the ISO after copying
Write-Host "Unmounting ISO..." -ForegroundColor Cyan
Dismount-DiskImage -ImagePath $HATISO
Write-Host "ISO Unmounted Successfully!" -ForegroundColor Green

Write-Host "File copy process completed for all deployment drives!" -ForegroundColor Green
Write-Host "Process completed successfully. Your USB is now bootable!" -ForegroundColor Cyan


# Stop Logging the script execution
Stop-Transcript
