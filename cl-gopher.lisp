(in-package :cl-gopher)

(defclass gopher-line ()
  ((line-type :initarg :line-type :accessor line-type)
   (display-string :initarg :display-string :accessor display-string)
   (selector :initarg :selector :accessor selector)
   (hostname :initarg :hostname :accessor hostname)
   (port :initarg :port :accessor port)))

(defclass search-line (gopher-line)
  ((terms :initform "" :initarg :terms :accessor terms)))

(defgeneric copy-gopher-line (gl))
(defmethod copy-gopher-line ((gl gopher-line))
  (make-instance 'gopher-line
                 :line-type (line-type gl)
                 :display-string (display-string gl)
                 :selector (selector gl)
                 :hostname (hostname gl)
                 :port (port gl)))

(defmethod copy-gopher-line ((gl search-line))
  (make-instance 'search-line
                 :line-type (line-type gl)
                 :display-string (display-string gl)
                 :selector (selector gl)
                 :hostname (hostname gl)
                 :port (port gl)
                 :terms (terms gl)))
  
(defmethod print-object ((gl gopher-line) stream)
  (print-unreadable-object (gl stream :type t)
    (format stream "Type: ~a, String: [~a], Selector: [~a], Host: [~a:~a]"
            (line-type gl) (display-string gl) (selector gl) (hostname gl) (port gl))))

(defun marshall-gopher-line (gl)
  (let ((lst))
    (push (cons :line-type (line-type gl)) lst)
    (push (cons :display-string (display-string gl)) lst)
    (push (cons :selector (selector gl)) lst)
    (push (cons :hostname (hostname gl)) lst)
    (push (cons :port (port gl)) lst)
    lst))

(defun marshall-gopher-lines (gls)
  (loop for line in gls
     collect (marshall-gopher-line line)))

(defun class-for-type (type)
  (case type
    (:search 'search-line)
    (t 'gopher-line)))

(defun unmarshall-gopher-line (gl)
  (let ((line-type (cdr (assoc :line-type gl))))
    (make-instance (class-for-type line-type)
                   :line-type (cdr (assoc :line-type gl))
                   :display-string (cdr (assoc :display-string gl))
                   :selector (cdr (assoc :selector gl))
                   :hostname (cdr (assoc :hostname gl))
                   :port (cdr (assoc :port gl)))))

(defun unmarshall-gopher-lines (gls)
  (loop for line in gls
       collect (unmarshall-gopher-line line)))

(defun type-for-character (c)
  (case c
    (#\0 :text-file)
    (#\1 :submenu)
    (#\2 :ccso-nameserver)
    (#\3 :error-code)
    (#\4 :binhex-file)
    (#\5 :dos-file)
    (#\6 :uuencoded-file)
    (#\7 :search)
    (#\8 :telnet)
    (#\9 :binary-file)
    (#\+ :mirror)
    (#\g :gif)
    (#\I :image)
    (#\p :png)
    (#\T :telnet-3270)
    (#\h :html-file)
    (#\i :info-message)
    (#\s :sound-file)
    (t :unknown)))

(defun str-elem (s n)
  (coerce (subseq s n (1+ n)) 'character))

(defun read-gopher-line (is)
  (let* ((line (read-line is nil nil)))
    (when (and line
               (not (equal line "."))
               (> (length line) 0))
      (let ((line-elems (split-sequence #\tab (subseq line 1)))
            (type (type-for-character (str-elem line 0))))
        (make-instance (class-for-type type)
                       :line-type type
                       :display-string (elt line-elems 0)
                       :selector (elt line-elems 1)
                       :hostname (elt line-elems 2)
                       :port (parse-integer (elt line-elems 3)))))))

(defmacro with-gopher-socket-for-selector ((stream host port selector) &rest body)
  (let ((sock (gensym "sock")))
    `(let* ((,sock (iolib:make-socket 
                    :external-format '(:ISO-8859-1 :eol-style :crlf)
                    :connect :active
                    :address-family :internet
                    :type :stream))
            (,stream (iolib:connect ,sock (iolib:lookup-hostname ,host) :port ,port))
            (babel-encodings:*suppress-character-coding-errors* t))
       (write-line ,selector ,stream)
       (force-output ,stream)
       ,@body)))

(defun gopher-get-directory (host port selector)
  (with-gopher-socket-for-selector (sock-stream host port selector)
    (loop for line = (cl-gopher::read-gopher-line sock-stream)
       while line
       collect line)))

(defun gopher-get-submenu (submenu)
  (when (eq (line-type submenu) :submenu)
    (gopher-get-directory (hostname submenu) (port submenu) (selector submenu))))

(defun gopher-do-search (search)
  (when (eq (line-type search) :search)
    (let ((selector (format nil "~a~a~a"
                            (cl-gopher::selector search)
                            #\tab
                            (terms search))))
      (gopher-get-directory (hostname search) (port search) selector))))

(defun display-line (line i)
  (case (line-type line)
    (:info-message (format t "~a~a~%" #\tab (display-string line)))
    (t (format t "~5a ~14a ~a ~a:~a~a~%"
               i
               (line-type line) (display-string line)
               (hostname line) (port line) (selector line)))))

(defun display-lines (lines)
  (loop for elem in lines
     for i from 0
     do (display-line elem i)))

(defun display-directory (host port selector)
  (let ((lines (gopher-get-directory host port selector)))
    (display-lines lines)
    lines))

(defun display-text-file (host port selector)
  (with-gopher-socket-for-selector (sock-stream host port selector)
    (loop for line = (read-line sock-stream nil nil)
       while line
       do (write-line line))))

(defun get-text-file-lines (host port selector)
  (with-gopher-socket-for-selector (sock-stream host port selector)
    (loop for line = (read-line sock-stream nil nil)
       while line
       collect line)))

(defun text-file-get-lines (text-file)
  (get-text-file-lines (hostname text-file) (port text-file) (selector text-file)))


(defun download-file (destfile host port selector)
  (with-gopher-socket-for-selector (sock-stream host port selector)
    (with-open-file (os destfile :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))
      (loop
         with arr = (make-array 2048 :element-type '(unsigned-byte 8))
         for count = (read-sequence arr sock-stream)
         while (> count 0)
         do (write-sequence arr os :end count)))))

(defun line-interactive (host port)
  (loop
     with elems = (list
                  (make-instance 'gopher-line
                                 :line-type :submenu
                                 :display-string "SDF.org"
                                 :selector "/"
                                 :hostname host
                                 :port port))
     for elem = (car elems)
     while (not (null elem))
     do
       (format t "gopher://~a:~a~a~%" (hostname elem) (port elem) (selector elem))
;       (let* ((lines (display-directory host port selector))
;               (choice (parse-integer (read-line)))
;               (elem (elt lines choice)))
;         (format t "Select a number to go: ~%")
;         (force-output *standard-output*)
       (case (line-type elem)
         (:submenu (let ((lines (display-directory (hostname elem) (port elem) (selector elem))))
                     (format t "Select a number to go: ~%")
                     (let ((choice (parse-integer (read-line))))
                       (if (< choice 0)
                           (pop elems)
                           (push (elt lines choice) elems)))))
         (:text-file (progn
                       (format t "Displaying text document. ~%")
                       (display-text-file (hostname elem) (port elem) (selector elem))
                       (format t "(return) to continue.~%")
                       (read-line)
                       (pop elems)))
         (:search (progn
                    (format t "Search for: ")
                    (force-output *standard-output*)
                    (let* ((search-string (read-line))
                           (mod-selector (format nil "~a~a~a" (selector elem) #\tab search-string)))
                      (pop elems)
                      (push
                       (make-instance 'gopher-line
                                      :line-type :submenu
                                      :display-string (display-string elem)
                                      :selector mod-selector
                                      :hostname (hostname elem)
                                      :port (port elem))
                       elems))))
                  
         (t (progn
              (format t "Unknown: ~a. Looping." (line-type elem))
              (pop elems))))))