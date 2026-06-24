# LSH

[![License](https://img.shields.io/badge/license-GPLv3-brightgreen)]()
[![Language](https://img.shields.io/badge/language-Ruby-red)]()
[![Version](https://img.shields.io/badge/version-1.0-green)]()

A lightweight **Unix shell written in Ruby**.

**LSH (Lightweight System Shell)** provides a familiar command-line experience
with persistent history, aliases, startup commands, and Bash-like tab completion,
all while remaining lightweight and easy to modify.

LSH aims to be a simple and hackable shell for everyday use.

---

## Features

* **Persistent command history**
* History stored in:

```bash
~/.lsh_history
```

* **Configuration file**

```bash
~/.lshrc
```

* **Alias support**
* **Startup commands**
* **Bash-style autocompletion**
* **Arrow key history navigation**
* **Colored prompt**
* **Built-in shell commands**
* **Ctrl+C and Ctrl+D support**
* **Single-file implementation**
* **Written entirely in Ruby**

---

## Usage

Run LSH:

```bash
ruby lsh.rb
```

Change directory:

```bash
cd Downloads
```

Reload configuration:

```bash
reload
```

View history:

```bash
history
```

Show loaded aliases and startup commands:

```bash
rcdebug
```

---

## Configuration

LSH automatically creates the following files on first launch:

```bash
~/.lshrc
~/.lsh_history
```

Default configuration:

```bash
# ~/.lshrc
# Uncomment aliases you want to use.

# alias ll='ls -lah'
# alias gs='git status'
# alias gc='git commit'
# alias gp='git push'
# alias gl='git pull'
# alias cls='clear'

# start = 'neofetch'
```

Example configuration:

```bash
alias gp='git push'
alias clean='pacman -Qdtq | sudo pacman -Rns -'

start = 'neofetch'
```

---

## Autocompletion

LSH provides Bash-style tab completion:

* Command completion
* File completion
* Directory completion
* Home directory completion (`~/`)
* Nested path completion
* Double-tab candidate listing
* Confirmation prompt for large result sets

Examples:

```bash
pac<TAB>
```

```bash
cd ~/Dow<TAB>
```

```bash
cat ~/Downloads/ls<TAB>
```

---

## Built-in Commands

```bash
cd
pwd
history
alias
unalias
export
source
reload
rcdebug
version
clear
exit
```

---

## Installation

### Clone Repository

```bash
git clone https://github.com/0xraincandy/lsh.git
cd lsh
```

### Run

```bash
ruby lsh.rb
```

### Install System-Wide

```bash
makepkg -si
```


---

## Known Limitations

* Not fully POSIX compliant
* Job control is not implemented
* Advanced Bash expansions are not supported
* Shell scripting support is limited

---

## Philosophy

LSH focuses on simplicity, readability, and hackability.

Instead of competing with Bash, Zsh, or Fish, LSH aims to provide a lightweight
shell that is easy to understand, modify, and extend.
