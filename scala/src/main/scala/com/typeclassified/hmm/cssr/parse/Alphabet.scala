package com.typeclassified.hmm.cssr.parse

object Alphabet {
  def apply(alphabetRaw: Array[Char]) = new Alphabet(alphabetRaw)
}

class Alphabet(alphabetRaw: Array[Char]) {
  val raw = alphabetRaw.filterNot("\r\n".contains(_))
  val map: Map[Char, Int]= raw.zipWithIndex.map { case (c: Char, i: Int) => c -> i }.toMap
  val length = raw.length

  override def toString: String = s"[${raw.mkString(", ")}]"
}

object AlphabetHolder {
  var alphabet: Alphabet = _
}


