export IDEA_PROPERTIES=$(dirname $0)/format.properties
exec "intellij-idea-ultimate" format "$@"
