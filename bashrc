# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
# don't overwrite GNU Midnight Commander's setting of `ignorespace'.
HISTCONTROL=$HISTCONTROL${HISTCONTROL+,}ignoredups
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
#case "$TERM" in
#xterm*|rxvt*)
#    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
#    ;;
#*)
#    ;;
#esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='grep -F --color=auto'
    alias egrep='grep -E --color=auto'
fi

# some more ls aliases
#alias ll='ls -l'
#alias la='ls -A'
#alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi


PATH=$HOME/bin:$PATH
export PYTHONSTARTUP=$HOME/git/dotfiles/pythonrc.py
#export PS1="\`if [ \$? = 0 ]; then echo ':)'; else echo ':('; fi\` \![\t]\u@\h[\W]\j:; "
#PS1="\`if [ \$? != 0 ]; then echo 'FAIL '; fi\`\!+\j[\t]\u@\h[\W]:; "
source $HOME/git/dotfiles/git-prompt.sh
#PS1="\!+\j[\t]\u@\h[\W\$(__git_ps1 "{%s}")]:; "

alias j=jobs
alias s=screen
alias sd='screen -dr'

complete -C "perl -e '@w=split(/ /,\$ENV{COMP_LINE},-1);\$w=pop(@w);for(qx(screen -ls)){print qq/\$1\n/ if (/^\s*\$w/&&/(\d+.*?)\s/||/\d+\.(\$w\w*)/)}'" screen
complete -C "perl -e '@w=split(/ /,\$ENV{COMP_LINE},-1);\$w=pop(@w);for(qx(screen -ls)){print qq/\$1\n/ if (/^\s*\$w/&&/(\d+.*?)\s||/\d+\.(\$w\w*)/)}'" s
complete -C "perl -e '@w=split(/ /,\$ENV{COMP_LINE},-1);\$w=pop(@w);for(qx(screen -ls)){print qq/\$1\n/ if (/^\s*\$w/&&/(\d+.*?)\s/||/\d+\.(\$w\w*)/)}'" sd


_complete_kubernetes_pod() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=( $(compgen -W "$(kubectl get pods|grep -v NAME | awk '{print $1}' | tr '\n' ' ')" -- $cur) )
}
complete -F _complete_kubernetes_pod kshell

rr() {
    eval "$(fc -ln -1) > /tmp/rr"
}

export EDITOR=vi
#eval "$(hub alias -s)"

if [ -f "$HOME/dotfiles/bashrc.local" ] ; then
    source $HOME/dotfiles/bashrc.local
fi

# Resolve Azure subscription name from ~/.azure/azureProfile.json
__azure_sub_name() {
    local sub="$1"
    local prof="$HOME/.azure/azureProfile.json"
    local name=""
    [ -f "$prof" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        name=$(jq -r --arg sub "$sub" '.subscriptions[]? | select(.id==$sub or .name==$sub) | .name' "$prof" 2>/dev/null | head -n1)
    else
        name=$(awk -v s="$sub" '
            {
              if (match($0, /"id"[[:space:]]*:[[:space:]]*"([^"]+)"/, m)) id=m[1]
              if (match($0, /"name"[[:space:]]*:[[:space:]]*"([^"]+)"/, n)) nm=n[1]
              if (id != "" && nm != "") {
                if (id==s || nm==s) { print nm; exit }
                id=""; nm=""
              }
            }
        ' "$prof" 2>/dev/null)
    fi
    [ -n "$name" ] || return 1
    printf "%s" "$name"
}

# Cloud context for prompt based on KUBECONFIG location (multi-cloud)
__cloud_ps1() {
    # Use the first kubeconfig path if multiple are set
    local kc="${KUBECONFIG%%:*}"
    [ -z "$kc" ] && return 0
    # Normalize $HOME
    local home="${HOME%/}"
    case "$kc" in
        "$home"/e/*/*)
            # GCP: ~/e/<project>/<cluster>
            local project cluster
            project=$(basename "$(dirname "$kc")")
            cluster=$(basename "$kc")
            printf " {gcp:%s/%s}" "$project" "$cluster"
            ;;
        "$home"/e-aws/*/*)
            # AWS: ~/e-aws/<profile>/<cluster>
            local profile cluster
            profile=$(basename "$(dirname "$kc")")
            cluster=$(basename "$kc")
            printf " {aws:%s/%s}" "$profile" "$cluster"
            ;;
        "$home"/e-azure/*/*)
            # Azure: ~/e-azure/<subscription>/<cluster>
            # Prefer human-friendly subscription name from local profile, avoid exposing full ID.
            local sub cluster account_dir name masked sublen first4 last4
            sub=$(basename "$(dirname "$kc")")
            account_dir="$(dirname "$kc")"
            cluster=$(basename "$kc")
            name=""
            # Prefer lookup from Azure CLI profile
            name="$(__azure_sub_name "$sub" 2>/dev/null || true)"
            # Else use already-exported name if present (from e/acc switch), else source local profile
            if [ -z "$name" ]; then
              if [ -n "$AZURE_SUBSCRIPTION_NAME" ]; then
                name="$AZURE_SUBSCRIPTION_NAME"
              elif [ -f "$account_dir/account.sh" ]; then
                # shellcheck disable=SC1090
                . "$account_dir/account.sh" >/dev/null 2>&1 || true
                name="${AZURE_SUBSCRIPTION_NAME:-${SUBSCRIPTION_NAME:-${AZ_SUBSCRIPTION_NAME:-}}}"
              fi
            fi
            if [ -n "$name" ]; then
              printf " {azure:%s/%s}" "$name" "$cluster"
            else
              # Fallback: mask long IDs, otherwise show the directory label
              sublen=${#sub}
              if [ "$sublen" -gt 8 ]; then
                first4=${sub:0:4}
                last4=${sub:$sublen-4:4}
                masked="${first4}...${last4}"
              else
                masked="$sub"
              fi
              printf " {azure:%s/%s}" "$masked" "$cluster"
            fi
            ;;
    esac
}

# Override PS1 to include Git and cloud context
PS1="\!+\j[\t]\u@\h[\W\$(__git_ps1 "{%s}")\$(__cloud_ps1)]:; "
export PYTHONWARNINGS="ignore::FutureWarning"
