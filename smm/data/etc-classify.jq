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
def ordinary($line; $stock):
  if ($line | test("^[[:space:]]*(#|$)")) or ($stock | index($line)) != null then
    .stock += [$line] | .review += [{action:"DROP",reason:"stock macOS (conservative fixture), blank or comment",line:$line}]
  else extra($line) end;
($stock | split("\n") | map(select(length > 0))) as $stocklines |
(split("\n") | if .[-1] == "" then .[:-1] else . end) |
reduce .[] as $line ({installer:[],stock:[],variables:{},shell:"",review:[],block:[]};
  if (.block | length) > 0 or ($line | test("^# Nix")) then
    .block += [$line] |
    if ($line | test("^# End Nix")) then
      .installer += .block | .review += [.block[] | {action:"DROP",reason:"Nix installer block (Nix manages initialization)",line:.}] | .block = []
    else . end
  else ordinary($line; $stocklines) end) |
# An incomplete installer block might contain user code: preserve it all.
reduce .block[] as $line (.; extra($line)) | del(.block)
