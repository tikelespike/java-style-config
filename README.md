<!-- TOC start (generated with https://github.com/derlin/bitdowntoc) -->

- [Java Codestyle Commit Hook](#java-codestyle-commit-hook)
   * [Setup](#setup)
      + [Prerequisites](#prerequisites)
      + [Installation](#installation)
   * [Usage and Configuration](#usage-and-configuration)
      + [Settings](#settings)
      + [Example](#example)

<!-- TOC end -->

<!-- TOC --><a name="java-codestyle-commit-hook"></a>
# Java Codestyle Commit Hook

![image](https://github.com/user-attachments/assets/5388e632-6850-41f7-ae0d-dbbb40734b60)


Never accidentally overlook code style violations in your Java code again! The script in this repository allows you to configure your local git installation in a way that prevents you from accidentally committing code that violates a checkstyle configuration. If you use IntelliJ IDEA, it can also ensure your autoformatter is applied correctly while checking in files.

The script is tested on Ubuntu 20.04. I cannot guarantee its functionality on other distributions.

This repository also contains example checkstyle and IntelliJ formatter configurations (tuned to my personal preferences) to get you started. Of course, you can also point the script to use your own configurations.

<!-- TOC --><a name="setup"></a>
## Setup

<!-- TOC --><a name="prerequisites"></a>
### Prerequisites

- If you intend to use the autoformatting feature, you need to have [IntelliJ IDEA](https://jetbrains.com/idea) installed.
- If you intend to use the checkstyle feature, you need to have [Checkstyle](https://checkstyle.sourceforge.io/) installed. You can do so by running `sudo apt-get install checkstyle`.

<!-- TOC --><a name="installation"></a>
### Installation

1. Clone this repository:
   
   ```sh
   git clone https://github.com/tikelespike/java-style-config.git
   ```
2. If you want to use the autoformatter feature: Open the `autoformatter.sh` script with a text editor of your choice. If necessary, replace `intellij-idea-ultimate` with the command line name of your IntelliJ installation (for example, if you use the Community Edition of IntelliJ). You can also use the `idea.sh` script included in every IntelliJ installation here.
3. In the git project repository where you want to use the hook (not this repository!), create the `.git/hooks/pre-commit` file if it does not exist yet, and make it executable:
   ```sh
   touch .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```
5. Open the `pre-commit` file with a text editor of your choice and make sure it contains (at least) the following (inserting your own path to this repo):
   ```sh
   #!/bin/sh 
   set -e
   /path/to/java-style-config/style-pre-commit-hook.sh
   ```
6. Try to run a git commit in the project repo and see if it works!
7. If you want, you can configure the hook as described below.

<!-- TOC --><a name="usage-and-configuration"></a>
## Usage and Configuration

By default, the script will (on every git commit):
1. Check if there is autoformatting yet to apply on any changed or new Java files
2. Check if there would be checkstyle violations even after applying the formatter, and if so, immediately cancel the commit
3. Check if there are checkstyle violations on the original files as you would have committed them
4. If there are no checkstyle violations or all of them can be fixed by applying the autoformatter, offer you to view the diff resulting from formatting and accept the changes (or commit anyways if there are no checkstyle violations at all)

While feature-rich, running the autoformatter every time (and checkstyle potentially multiple times) is slow. Especially the autoformatter takes quite some time on every commit. You can customize how the different tools are used, as well as which style configurations are used.

To change a setting, make sure the corresponding environment variable is set accordingly, either by editing the default value in the `style-pre-commit-hook.sh` script directly or by adding a line similar to the following to the `pre-commit` file in the respective repo (before calling the hook)

```sh
export ALLOW_IGNORE_CHECKSTYLE=true # I am not a child, let me decide for myself if I want to adhere to checkstyle or not
```

<!-- TOC --><a name="settings"></a>
### Settings

| Variable                           | Allowed Values                                                                 | Default Value                                               | Effect                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
|------------------------------------|--------------------------------------------------------------------------------|-------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `USE_AUTOFORMATTER`                | `true`, `false`                                                                | `true`                                                      | If false, only a simple checkstyle validation on the changed files is made and the autoformatter is not run.                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `USE_CHECKSTYLE`                   | `true`, `false`                                                                | `true`                                                      | If false, the script only checks if autoformatting can be applied and never runs checkstyle.                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `AUTOFORMATTER_CONFIG`             | valid filesystem path pointing to an IntelliJ formatter configuration XML file | path to the `autoformat_intellij.xml` included in this repo | Configures the exact style used by the autoformatter. You can [export this from the IDE](https://www.jetbrains.com/help/idea/configuring-code-style.html#export-code-style).                                                                                                                                                                                                                                                                                                                                                          |
| `CHECKSTYLE_CONFIG`                | valid filesystem path pointing to a checkstyle configuration XML file          | path to the `checkstyle.xml` included in this repo          | Configures the exact style checks validated by checkstyle. See also the [checkstyle docs](https://checkstyle.sourceforge.io/checks.html)                                                                                                                                                                                                                                                                                                                                                                                              |
| `ALLOW_IGNORE_CHECKSTYLE`          | `true`, `false`                                                                | `false`                                                     | If true, you can always force to commit anyways, but you will still be warned that you are violating checkstyle. Has no effect if `USE_CHECKSTYLE` is false.                                                                                                                                                                                                                                                                                                                                                                          |
| `NO_FORMATTING_WHEN_CHECKSTYLE_OK` | `true`, `false`                                                                | `false`                                                     | Set this to true to skip running the autoformatter if there are no checkstyle violations. The use case is that you only care about checkstyle, but like that some checkstyle issues can be fixed automatically be applying the autoformatter. This saves time because the autoformatter is not always run, but will not detect if you are checking in code that is not yet formatted by the autoformatter (if this doesn't lead to checkstyle violations). Has no effect if either `USE_CHECKSTYLE` or `USE_AUTOFORMATTER` are false. |

<!-- TOC --><a name="example"></a>
### Example

Example `pre-commit` file:

```sh
#!/bin/sh 
set -e
export CHECKSTYLE_CONFIG=/path/to/another/custom-checkstyle.xml
export ALLOW_IGNORE_CHECKSTYLE=true
export NO_FORMATTING_WHEN_CHECKSTYLE_OK=true
/path/to/java-style-config/style-pre-commit-hook.sh
```
Here's how the script would behave with this configuration:

1. First of all, run checkstyle on all staged files (using the specified `custom-checkstyle.xml`). If there are no violations, we are good to go and the commit will continue as normal with you entering the message.
2. But if there are checkstyle violations: Run the autoformatter (using the configuration file of this repo). If this would result in no changes: Tell the user there is nothing to do for the formatter, but there are still checkstyle violations. User can choose whether to commit anyway (because of `ALLOW_IGNORE_CHECKSTYLE`) or to cancel the commit.
   
   ![image](https://github.com/user-attachments/assets/a41ff573-a309-46d3-b74a-9d75ecb1f82a)
   
3. If there is work to do for the autoformatter: Verify if formatted files would be checkstyle-compliant.
4. If applying the autoformatter would result in changes that would fix all checkstyle issues: User can choose to accept changes, view diff created by autoformatter, commit anyway (with a warning that checkstyle will be violated), or cancel the commit.
   
   ![image](https://github.com/user-attachments/assets/5c3438d7-1c81-4db6-95fb-3be5c32a3012)
   
5. If applying the autoformatter would result in changes that would not fix all checkstyle issues: User can choose to accept changes (with a warning that there will still be checkstyle violations), view diff, commit anyway (with checkstyle warning), or cancel the commit.

   ![image](https://github.com/user-attachments/assets/fcdeb5e1-11ad-4031-8ffa-d6ab36cb8c75)

6. Depending on the users choice, cancel the commit or continue as normal.
