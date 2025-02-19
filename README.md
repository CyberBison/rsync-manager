
# rsync-manager

**Author**: CyberBison  
**License**: GPL-3.0  
**Current version**: 1.0.2
**Changelog**: [View here](https://rsync.cyberbison.dev/changelog)

This project is still in its early stages, and more features are being actively developed.

---

## Overview

`rsync-manager` is a lightweight macOS app designed to simplify `rsync` backups. It provides an intuitive interface for creating, editing, and executing backup tasks, making it easier to manage your data synchronization workflows without needing to remember complex terminal commands.

### **Key Features**
- **Task Management**: Create and configure multiple `rsync` tasks effortlessly.
- **Easy Folder Selection**: Select source and destination directories via a clean user interface.
- **Manual Execution**: Execute backup tasks directly from the app.
- **Planned Enhancements**:
  - **Sync History**: Track the last execution time for each task.
  - **Scheduled Backups**: Automate tasks on a customizable schedule.
  - **Notifications**: Get notified of sync progress and errors.

---

## Requirements

- **macOS**: Version 14.6 or higher
- **Homebrew**: For easy installation (optional but recommended)

---

## Installation

### Option 1: Install via Homebrew
1. Tap the custom Homebrew repository:
   ```bash
   brew tap cyberbison/custombrew
   ```
2. Install the app:
   ```bash
   brew install --cask rsync-manager
   ```

### Option 2: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/CyberBison/rsync-manager.git
   cd rsync-manager
   ```
2. Open the project in Xcode:
   ```bash
   open rsync-manager.xcodeproj
   ```
3. Build and run the app.

---

## Getting Started

1. Launch `rsync-manager` from your Applications folder or via Spotlight.
2. Use the **Add Task** button to define your first backup task:
   - Select the source folder.
   - Select the destination folder.
3. Run tasks with a single click or edit existing tasks to fine-tune settings.

---

## Contributing

Contributions are welcome! Feel free to submit issues or feature requests via the [GitHub Issues](https://github.com/CyberBison/rsync-manager/issues) page. For larger contributions, please fork the repository and submit a pull request.

---

## Support

If you encounter any issues or have questions, please reach out via [GitHub Discussions](https://github.com/CyberBison/rsync-manager/discussions).

---

## License

This project is licensed under the [GPL-3.0 License](https://www.gnu.org/licenses/gpl-3.0.en.html).

---

Thank you for using `rsync-manager`! 🚀
