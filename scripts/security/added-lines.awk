# Input is a normalized Git patch with fixed a/ and b/ prefixes.
# Keep Git quoting for unusual names so diagnostics stay on one line.
/^diff / { in_hunk = 0; path = ""; next }
!in_hunk && /^\+\+\+ / {
  path = substr($0, 5)
  sub(/\t$/, "", path)
  if (path ~ /^b\//) path = substr(path, 3)
  else if (path ~ /^"b\//) path = "\"" substr(path, 4)
  next
}
/^@@ / {
  header = $0
  sub(/^@@ -[0-9]+(,[0-9]+)? \+/, "", header)
  sub(/[, ].*$/, "", header)
  new_line = header + 0
  in_hunk = 1
  next
}
in_hunk && /^\+/ {
  print substr($0, 2)
  print ++added_count "\t" path "\t" new_line > ENVIRON["LINE_MAP"]
  new_line++
  next
}
in_hunk && /^ / { new_line++ }
