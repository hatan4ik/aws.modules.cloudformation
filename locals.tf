locals {
  # The module adds only a Name tag, and a caller's Name wins.
  tags = merge({ Name = var.name }, var.tags)
}
