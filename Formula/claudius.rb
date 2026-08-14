class Claudius < Formula
  desc "Manage, resume, and summarise Claude Code conversations by name"
  homepage "https://github.com/SaxenaKartik/claudius"
  url "https://github.com/SaxenaKartik/claudius/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "4b57f676b523bbe91a9f5df0a8b84592ba7474b8da81fe40542b81e39957ffb1"
  license "MIT"

  def install
    (share/"claudius").install "claudius.zsh"
    (share/"claudius/commands").install Dir["commands/*.md"]
  end

  def caveats
    <<~EOS
      Claudius is a set of zsh functions + Claude Code slash commands.

      1) Load the shell helpers — add to your ~/.zshrc:
           source "#{opt_share}/claudius/claudius.zsh"

      2) Install the slash commands for Claude Code:
           mkdir -p ~/.claude/commands
           ln -sf #{opt_share}/claudius/commands/*.md ~/.claude/commands/

      Then:  source ~/.zshrc   and run   cchelp
      Requires zsh and Claude Code (`claude` on PATH).
    EOS
  end

  test do
    output = shell_output("zsh -c 'source #{share}/claudius/claudius.zsh; cchelp'")
    assert_match "Claudius", output
  end
end
