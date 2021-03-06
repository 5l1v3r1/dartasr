library dartasr;

import 'dart:math';
import '../frame_processor.dart';
import '../framedata.dart';
import '../../math/log_math.dart';

/**
 * Creates a Mel Frequency Filter Bank and applies the filter to input power spectrum values.
 * It uses a similar technique used in Sphinx4 but implementation is different.
 */
class MelFilterBank implements FrameProcessor {
  
  double minFreq;
  double maxFreq;
  int filterAmount;
  List<MelFilter> filters;
  int energySpectrumSize;
  int sampleRate;
  int liftFreq;

  MelFilterBank(this.minFreq, this.maxFreq, this.filterAmount, this.sampleRate, this.energySpectrumSize, [liftFreq]) {
    if (minFreq < 0)
      throw new ArgumentError("Minimum frequency value cannot be negative but it is: $minFreq");
    if (maxFreq <= 0)
      throw new ArgumentError("Maximum frequency value must be positive but it is: $maxFreq");
    if (minFreq >= maxFreq)
      throw new ArgumentError("Minimum frequency value must be smaller than maximum frequency value. But MinFreq= $minFreq MaxFreq= $maxFreq");
    filters = new List<MelFilter>(filterAmount);
    this.liftFreq = ?liftFreq ? liftFreq : 0;
    generateFilters();
  }

  FrameData process(FrameData input) {
    return input.copy(applyFilter(input));
  }

  List<double> applyFilter(FrameData input) {
    var result = new List<double>(filterAmount);
    int j = 0;
    for (MelFilter filter in filters) {
      result[j++] = filter.apply(input.data);
    }
    return result;
  }

  /**
   * Calculates linearly separated mel frequency values.
  *
   * @return mel frequency values (size = filterAmount)
   */
  List<double> calculateMelFrequencies() {
    var freqValues = new List<double>(filterAmount);
    double minMelFreq = linearToMel(minFreq);
    double maxMelFreq = linearToMel(maxFreq);
    double interval = (maxMelFreq - minMelFreq) / (filterAmount + 1);
    double value = minMelFreq;
    int i = 0;
    while (i < filterAmount) {
      value += interval;
      freqValues[i] = value;
      i++;
    }
    return freqValues;
  }

  void generateFilters() {
    // calculate mel center frequencies with same intervals.
    Float64List melFreqs = calculateMelFrequencies();

    // calculate equivalent linear center frequencies
    var centerFreqs = new List<double>(melFreqs.length);
    for (int i = 0; i < centerFreqs.length; i++) {
      centerFreqs[i] = melToLinear(melFreqs[i]);
    }

    // this represents the actual frequency difference between each fft sample.
    double step = ( sampleRate / 2.0) / energySpectrumSize;

    // now generate a triangular filter for each center frequency.
    for (int i = 0; i < centerFreqs.length; i++) {
      double left;
      if (i == 0)
        left = minFreq;
      else
        left = centerFreqs[i - 1];

      double right;
      if (i == filterAmount - 1)
        right = maxFreq;
      else
        right = centerFreqs[i + 1];

      filters[i] = createFilter(left, centerFreqs[i], right, step);
    }
  }

  MelFilter createFilter(double left, double center, double right, double step) {
    int leftStart = (left~/step + 1).toInt(); // inclusive
    int middle =  (center~/step + 1).toInt(); // exclusive for left side inclusive for right side
    int rightEnd =  (right~/step + 1).toInt(); // exclusive

    int totalWeights = rightEnd - leftStart;
    if (totalWeights == 0)
      throw new ExpectException("There is no frequency value in filter bank limits!");

    var weights = new List<double>(totalWeights);

    // we assume triangles are with the area of 1. So we calculate the height.
    // This is the standard procedure in sphinx-3,4
    double height = 2.0  /(right-left);

    double leftSlope = height / (center - left + liftFreq);
    final int leftSize = middle - leftStart;
    for (int i = 0; i < leftSize; i++) {
      weights[i] = ((i + leftStart) * step - left + liftFreq) * leftSlope;
    }

    double rightSlope = height / (right - center + liftFreq);
    for (int i = 0; i < rightEnd - middle; i++) {
      weights[i + leftSize] = (right + liftFreq - (i + middle) * step) * rightSlope;
    }

    return new MelFilter(leftStart, rightEnd, weights);
  }
  
} 

class MelFilter {
  int sampleStart;
  int sampleEnd;
  List<double> weights;

  MelFilter(int sampleStart, int sampleEnd, List<double> weights) {
    this.sampleStart = sampleStart;
    this.sampleEnd = sampleEnd;
    this.weights = weights;
  }

  double apply(List<double> samples) {
    double result = 0.0;
    for (int j = sampleStart; j < sampleEnd; j++) {
      result += (samples[j] * weights[j-sampleStart]);
    }
    return result;
  }
}

/** Converts to Linear frequency value to Mel frequency value. */
linearToMel(double linearFreq) {
  return 2595.0 * log10(1.0 + linearFreq / 700.0);
}

/** Converts Mel frequency to linear frequency value. */
melToLinear(double melFreq) {
  return 700.0 * (pow(10.0, (melFreq / 2595.0)) - 1.0);
}
