(in-package #:first-class-lambda-lists)

(defclass fcll:lambda-list () ())

(defclass fcll:standard-lambda-list (fcll:lambda-list)
  ((%kind :reader kind
          :type fcll:lambda-list-kind)
   (%sections :reader %sections
              :type list
              :initform nil)))

(defmethod shared-initialize :after ((instance fcll:standard-lambda-list) slot-names &key kind)
  (setf (slot-value instance '%kind)
        (defsys:locate *lambda-list-kind-definitions* kind)))

(defmethod print-object ((lambda-list fcll:standard-lambda-list) stream)
  (print-unreadable-object (lambda-list stream :type t)
    (format stream "~S ~S"
            (defsys:name (kind lambda-list))
            (%sections lambda-list))))

(defgeneric reset (object))

(defmethod reset ((lambda-list fcll:standard-lambda-list))
  (setf (slot-value lambda-list '%sections) nil))


(defgeneric parse-lambda-list (lambda-list specification))

(defmethod parse-lambda-list ((lambda-list fcll:standard-lambda-list) specification)
  (setf (slot-value lambda-list '%sections)
        (funcall (parser (kind lambda-list)) specification)))
