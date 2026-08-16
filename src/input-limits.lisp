;;; UTF-8 byte accounting shared by the HTTP and streaming boundaries.
#.(progn (in-package :ollama-kit) nil)

(defun %utf8-character-octets (character)
  "Return the number of UTF-8 octets required for CHARACTER."
  (let ((code-point (char-code character)))
    (cond
      ((<= code-point #x7f) 1)
      ((<= code-point #x7ff) 2)
      ((<= code-point #xffff) 3)
      (t 4))))

(defun %utf8-octet-length (string)
  "Return STRING's length in UTF-8 octets rather than characters."
  (loop for character across string
        sum (%utf8-character-octets character)))
