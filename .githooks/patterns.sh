# Shared by the hooks in this directory. Source, do not run.
#
# Every commit here is authored by the repository owner alone: no commit may
# be authored or committed as Claude, and no message may carry an assistant
# attribution line.

# Author or committer identity, as "Name <email>".
bad_ident='^Claude( |$)|@anthropic\.com>'
# Lines of a commit message.
bad_line='^(co-authored-by|assisted-by|generated-by):.*(claude|anthropic)|^claude-session:|generated with \[?claude|noreply@anthropic\.com'

owner_name='Hung-Kuan Tseng'
owner_email='tseng.tim096@gmail.com'

# Prints the offending lines of the message on stdin, if any.
bad_message_lines() {
  grep -n -i -E "$bad_line"
}

# is_bad_ident "Name <email>"
is_bad_ident() {
  printf '%s\n' "$1" | grep -q -i -E "$bad_ident"
}
