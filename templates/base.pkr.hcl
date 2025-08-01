packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "macos_version" {
  type = string
}

source "tart-cli" "tart" {
  vm_base_name = "ghcr.io/cirruslabs/macos-${var.macos_version}-vanilla:latest"
  vm_name      = "${var.macos_version}-base"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "file" {
    source      = "data/limit.maxfiles.plist"
    destination = "~/limit.maxfiles.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'Configuring maxfiles...'",
      "sudo mv ~/limit.maxfiles.plist /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist",
      "echo 'Disabling spotlight...'",
      "sudo mdutil -a -i off",
    ]
  }

  # Create a symlink for bash compatibility
  provisioner "shell" {
    inline = [
      "touch ~/.zprofile",
      "ln -s ~/.zprofile ~/.profile",
    ]
  }

  provisioner "shell" {
    inline = [
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      "echo \"export LANG=en_US.UTF-8\" >> ~/.zprofile",
      "echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_AUTO_UPDATE=1\" >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_INSTALL_CLEANUP=1\" >> ~/.zprofile",
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew --version",
      "brew update",
      "brew install wget unzip zip ca-certificates cmake gcc git-lfs jq yq gh gitlab-runner",
      "brew install curl || true", // doesn't work on Monterey
      "brew install --cask git-credential-manager",
      "git lfs install",
      "sudo softwareupdate --install-rosetta --agree-to-license"
    ]
  }

  // Add GitHub to known hosts
  // Similar to https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-ssh.sh
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh"
    ]
  }
  provisioner "file" {
    source      = "data/github_known_hosts"
    destination = "~/.ssh/known_hosts"
  }

  // Install the GitHub Actions runner
  provisioner "shell" {
    script = "scripts/install-actions-runner.sh"
  }

  // Create a /Users/runner → /Users/admin symlink to support certain GitHub Actions
  // like ruby/setup-ruby that hard-code the "/Users/runner/hostedtoolcache" path[1]
  //
  // [1]: https://github.com/ruby/setup-ruby/blob/6bd3d993c602f6b675728ebaecb2b569ff86e99b/common.js#L268
  provisioner "shell" {
    inline = [
      "sudo ln -s /Users/admin /Users/runner"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install libyaml", # https://github.com/rbenv/ruby-build/discussions/2118
      "brew install rbenv",
      "echo 'if which rbenv > /dev/null; then eval \"$(rbenv init -)\"; fi' >> ~/.zprofile",
      "source ~/.zprofile",
      "rbenv install 2.7.8", // latest 2.x.x before EOL
      "rbenv install -l | grep -v - | tail -2 | xargs -L1 rbenv install",
      "rbenv global $(rbenv install -l | grep -v - | tail -1)",
      "gem install bundler",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install node@20",
      "echo 'export PATH=\"/opt/homebrew/opt/node@20/bin:$PATH\"' >> ~/.zprofile",
      "source ~/.zprofile",
      "node --version",
      "npm install --global yarn",
      "yarn --version",
    ]
  }
  provisioner "shell" {
    inline = [
      "sudo safaridriver --enable",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install awscli"
    ]
  }

  # Enable UI automation, see https://github.com/cirruslabs/macos-image-templates/issues/136
  provisioner "shell" {
    script = "scripts/automationmodetool.expect"
  }

  // some other health checks
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "test -d /Users/runner",
      "test -f ~/.ssh/known_hosts"
    ]
  }

  // Guest agent for Tart VMs
  provisioner "file" {
    source      = "data/tart-guest-daemon.plist"
    destination = "~/tart-guest-daemon.plist"
  }
  provisioner "file" {
    source      = "data/tart-guest-agent.plist"
    destination = "~/tart-guest-agent.plist"
  }
  provisioner "shell" {
    inline = [
      # Install Tart Guest Agent
      "source ~/.zprofile",
      "brew install cirruslabs/cli/tart-guest-agent",

      # Install daemon variant of the Tart Guest Agent
      "sudo mv ~/tart-guest-daemon.plist /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/org.cirruslabs.tart-guest-daemon.plist",

      # Install agent variant of the Tart Guest Agent
      "sudo mv ~/tart-guest-agent.plist /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "sudo chown root:wheel /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "sudo chmod 0644 /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
    ]
  }
}
