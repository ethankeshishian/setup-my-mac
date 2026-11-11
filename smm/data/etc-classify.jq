def extra($line):
  # Accept only literal assignments. Shell expansions, escapes, compound commands
  # and unbalanced quotes remain verbatim shell init; never evaluate shell text.
  ((try ($line | capture("^export (?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$")) catch null) // null) as $assignment |
  if $assignment != null and
    ($assignment.value | test("^(?:[A-Za-z0-9_./:@%+,=-]+|'[^']*'|\"[^\"$`\\\\]*\")$")) then
    ($assignment.value | if startswith("'") or startswith("\"") then .[1:-1] else . end) as $value |
    .variables[$assignment.name] = $value |
    .review += [{action:"KEEP",reason:("environment.variables." + $assignment.name),line:$line}]
  else .shell += ($line + "\n") | .review += [{action:"KEEP",reason:"shell init (uncertain lines preserved)",line:$line}] end;
def normalize: gsub("^[[:space:]]+|[[:space:]]+$"; "");
# Match complete stock conditionals, so stock-looking fi/else lines and literal
# exports inside a custom conditional stay in their original shell context.
def multiline_if:
  test("^[[:space:]]*if[[:space:]]") and
  (test(";[[:space:]]*fi[[:space:]]*;?[[:space:]]*$") | not);
def code_tokens: map(normalize | select(length > 0 and (startswith("#") | not)));
def keep_shell($lines):
  if ($lines | length) == 0 then . else
    .shell += (($lines | join("\n")) + "\n") |
    .review += [$lines[] | {action:"KEEP",reason:"shell init (uncertain block preserved)",line:.}]
  end;
def finish_code($stock):
  .codeblock as $lines |
  if ("\n" + ($stock | code_tokens | join("\n")) + "\n" |
      contains("\n" + ($lines | code_tokens | join("\n")) + "\n")) then
    .stock += $lines |
    .review += [$lines[] | {action:"DROP",reason:"stock macOS conditional (conservative fixture)",line:.}]
  else keep_shell($lines) end |
  .codeblock = [] | .codedepth = 0;
def ordinary($line; $stock):
  if ($line | test("^[[:space:]]*(#|$)")) or ($stock | index($line | normalize)) != null then
    .stock += [$line] | .review += [{action:"DROP",reason:"stock macOS (conservative fixture), blank or comment",line:$line}]
  else extra($line) end;
($stock | split("\n") | map(select(length > 0) | normalize)) as $stocklines |
(split("\n") | if .[-1] == "" then .[:-1] else . end) |
reduce .[] as $line ({installer:[],stock:[],variables:{},shell:"",review:[],block:[],ssh:false,depth:0,codeblock:[],codedepth:0};
  if (.codeblock | length) > 0 then
    .codeblock += [$line] |
    if ($line | multiline_if) then .codedepth += 1 else . end |
    if ($line | test("^[[:space:]]*fi[[:space:]]*;?[[:space:]]*$")) then
      .codedepth -= 1 |
      if .codedepth == 0 then finish_code($stocklines) else . end
    else . end
  elif ($line | test("^# Set up Nix only on SSH connections")) and (.block | length) == 0 then
    .ssh = true | .block = [$line] | .depth = 0
  elif .ssh then
    .block += [$line] |
    if ($line | test("^[[:space:]]*if[[:space:]]")) then .depth += 1 else . end |
    if ($line | test("^[[:space:]]*fi[[:space:]]*;?[[:space:]]*$")) then
      .depth -= 1 |
      if .depth == 0 then
        .installer += .block | .review += [.block[] | {action:"DROP",reason:"Nix installer SSH block (Nix manages initialization)",line:.}] |
        .block = [] | .ssh = false
      else . end
    else . end
  elif (.block | length) > 0 or ($line | test("^# Nix")) then
    .block += [$line] |
    if ($line | test("^# End Nix")) then
      .installer += .block | .review += [.block[] | {action:"DROP",reason:"Nix installer block (Nix manages initialization)",line:.}] | .block = []
    else . end
  elif ($line | multiline_if) then .codeblock = [$line] | .codedepth = 1
  else ordinary($line; $stocklines) end) |
# An incomplete installer block might contain user code: preserve it all.
reduce .block[] as $line (.; extra($line)) |
keep_shell(.codeblock) | del(.block,.ssh,.depth,.codeblock,.codedepth)
