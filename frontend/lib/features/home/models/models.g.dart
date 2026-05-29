// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AchievementAdapter extends TypeAdapter<Achievement> {
  @override
  final int typeId = 1;

  @override
  Achievement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Achievement(
      id: fields[0] as String,
      title: fields[1] as String,
      icon: fields[2] as String,
      category: fields[3] as String,
      isUnlocked: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Achievement obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.icon)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.isUnlocked);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AchievementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 2;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      displayName: fields[0] as String,
      avatarImageUrl: fields[1] as String?,
      userType: fields[2] as UserType,
      currentLevel: fields[3] as int,
      levelTitle: fields[4] as String,
      currentXP: fields[5] as int,
      xpToNextLevel: fields[6] as int,
      startingWeight: fields[7] as double,
      weightGoal: fields[8] as double,
      primaryGoal: fields[9] as String,
      recentAchievements: (fields[10] as List).cast<Achievement>(),
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.displayName)
      ..writeByte(1)
      ..write(obj.avatarImageUrl)
      ..writeByte(2)
      ..write(obj.userType)
      ..writeByte(3)
      ..write(obj.currentLevel)
      ..writeByte(4)
      ..write(obj.levelTitle)
      ..writeByte(5)
      ..write(obj.currentXP)
      ..writeByte(6)
      ..write(obj.xpToNextLevel)
      ..writeByte(7)
      ..write(obj.startingWeight)
      ..writeByte(8)
      ..write(obj.weightGoal)
      ..writeByte(9)
      ..write(obj.primaryGoal)
      ..writeByte(10)
      ..write(obj.recentAchievements);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GlucoseReadingAdapter extends TypeAdapter<GlucoseReading> {
  @override
  final int typeId = 5;

  @override
  GlucoseReading read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GlucoseReading(
      timestamp: fields[0] as DateTime,
      value: fields[1] as double,
      trend: fields[2] as GlucoseTrend,
      status: fields[3] as GlucoseStatus,
    );
  }

  @override
  void write(BinaryWriter writer, GlucoseReading obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.trend)
      ..writeByte(3)
      ..write(obj.status);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlucoseReadingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ActivitySummaryAdapter extends TypeAdapter<ActivitySummary> {
  @override
  final int typeId = 6;

  @override
  ActivitySummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActivitySummary(
      steps: fields[0] as int,
      calories: fields[1] as int,
      activeMinutes: fields[2] as int,
      heartRate: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ActivitySummary obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.steps)
      ..writeByte(1)
      ..write(obj.calories)
      ..writeByte(2)
      ..write(obj.activeMinutes)
      ..writeByte(3)
      ..write(obj.heartRate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivitySummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SleepDataAdapter extends TypeAdapter<SleepData> {
  @override
  final int typeId = 7;

  @override
  SleepData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SleepData(
      totalHours: fields[0] as double,
      stages: (fields[1] as List).cast<SleepStage>(),
    );
  }

  @override
  void write(BinaryWriter writer, SleepData obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.totalHours)
      ..writeByte(1)
      ..write(obj.stages);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SleepStageAdapter extends TypeAdapter<SleepStage> {
  @override
  final int typeId = 8;

  @override
  SleepStage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SleepStage(
      type: fields[0] as SleepStageType,
      hours: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, SleepStage obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.hours);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepStageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CoachInsightAdapter extends TypeAdapter<CoachInsight> {
  @override
  final int typeId = 10;

  @override
  CoachInsight read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CoachInsight(
      title: fields[0] as String,
      description: fields[1] as String,
      category: fields[2] as String,
      estimatedSavingUnits: fields[3] as double,
      progress: fields[4] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CoachInsight obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.estimatedSavingUnits)
      ..writeByte(4)
      ..write(obj.progress);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachInsightAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class WeightEntryAdapter extends TypeAdapter<WeightEntry> {
  @override
  final int typeId = 11;

  @override
  WeightEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WeightEntry(
      timestamp: fields[0] as DateTime,
      weight: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, WeightEntry obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.weight);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeightEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NutritionSummaryAdapter extends TypeAdapter<NutritionSummary> {
  @override
  final int typeId = 12;

  @override
  NutritionSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NutritionSummary(
      calories: fields[0] as int,
      carbsG: fields[1] as int,
      proteinG: fields[2] as int,
      fatG: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, NutritionSummary obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.calories)
      ..writeByte(1)
      ..write(obj.carbsG)
      ..writeByte(2)
      ..write(obj.proteinG)
      ..writeByte(3)
      ..write(obj.fatG);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionSummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LoggedMealAdapter extends TypeAdapter<LoggedMeal> {
  @override
  final int typeId = 14;

  @override
  LoggedMeal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LoggedMeal(
      id: fields[0] as String,
      name: fields[1] as String,
      timestamp: fields[2] as DateTime,
      calories: fields[3] as int,
      carbsG: fields[4] as int,
      proteinG: fields[5] as int,
      fatG: fields[6] as int,
      glycaemicLoad: fields[7] as double,
      estimatedRiseMinutes: fields[8] as int,
    );
  }

  @override
  void write(BinaryWriter writer, LoggedMeal obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.calories)
      ..writeByte(4)
      ..write(obj.carbsG)
      ..writeByte(5)
      ..write(obj.proteinG)
      ..writeByte(6)
      ..write(obj.fatG)
      ..writeByte(7)
      ..write(obj.glycaemicLoad)
      ..writeByte(8)
      ..write(obj.estimatedRiseMinutes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggedMealAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GlucosePointAdapter extends TypeAdapter<GlucosePoint> {
  @override
  final int typeId = 15;

  @override
  GlucosePoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GlucosePoint(
      time: fields[0] as DateTime,
      value: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, GlucosePoint obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.time)
      ..writeByte(1)
      ..write(obj.value);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlucosePointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TIRBreakdownAdapter extends TypeAdapter<TIRBreakdown> {
  @override
  final int typeId = 16;

  @override
  TIRBreakdown read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TIRBreakdown(
      below: fields[0] as double,
      target: fields[1] as double,
      above: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, TIRBreakdown obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.below)
      ..writeByte(1)
      ..write(obj.target)
      ..writeByte(2)
      ..write(obj.above);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TIRBreakdownAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CGMStateAdapter extends TypeAdapter<CGMState> {
  @override
  final int typeId = 17;

  @override
  CGMState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CGMState(
      currentGlucose: fields[0] as int,
      trend: fields[1] as GlucoseTrend,
      lastUpdatedMinutesAgo: fields[2] as int,
      currentStatus: fields[3] as GlucoseStatus,
      last24Hours: (fields[4] as List).cast<GlucosePoint>(),
      timeInRange24h: fields[5] as double,
      averageGlucose28Days: fields[6] as double,
      timeInRangeBreakdown: fields[7] as TIRBreakdown,
    );
  }

  @override
  void write(BinaryWriter writer, CGMState obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.currentGlucose)
      ..writeByte(1)
      ..write(obj.trend)
      ..writeByte(2)
      ..write(obj.lastUpdatedMinutesAgo)
      ..writeByte(3)
      ..write(obj.currentStatus)
      ..writeByte(4)
      ..write(obj.last24Hours)
      ..writeByte(5)
      ..write(obj.timeInRange24h)
      ..writeByte(6)
      ..write(obj.averageGlucose28Days)
      ..writeByte(7)
      ..write(obj.timeInRangeBreakdown);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CGMStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NutritionStateAdapter extends TypeAdapter<NutritionState> {
  @override
  final int typeId = 18;

  @override
  NutritionState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NutritionState(
      caloriesEaten: fields[0] as int,
      calorieTarget: fields[1] as int,
      carbsEaten: fields[2] as double,
      proteinEaten: fields[3] as double,
      fatEaten: fields[4] as double,
      caloriesRemaining: fields[5] as int,
      todaysMeals: (fields[6] as List).cast<LoggedMeal>(),
    );
  }

  @override
  void write(BinaryWriter writer, NutritionState obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.caloriesEaten)
      ..writeByte(1)
      ..write(obj.calorieTarget)
      ..writeByte(2)
      ..write(obj.carbsEaten)
      ..writeByte(3)
      ..write(obj.proteinEaten)
      ..writeByte(4)
      ..write(obj.fatEaten)
      ..writeByte(5)
      ..write(obj.caloriesRemaining)
      ..writeByte(6)
      ..write(obj.todaysMeals);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ActivityStateAdapter extends TypeAdapter<ActivityState> {
  @override
  final int typeId = 19;

  @override
  ActivityState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActivityState(
      stepsToday: fields[0] as int,
      stepTarget: fields[1] as int,
      caloriesBurned: fields[2] as int,
      activeMinutes: fields[3] as int,
      heartRate: fields[4] as int,
      stepHistory: (fields[5] as List).cast<DailyValue>(),
    );
  }

  @override
  void write(BinaryWriter writer, ActivityState obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.stepsToday)
      ..writeByte(1)
      ..write(obj.stepTarget)
      ..writeByte(2)
      ..write(obj.caloriesBurned)
      ..writeByte(3)
      ..write(obj.activeMinutes)
      ..writeByte(4)
      ..write(obj.heartRate)
      ..writeByte(5)
      ..write(obj.stepHistory);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CoachStateAdapter extends TypeAdapter<CoachState> {
  @override
  final int typeId = 20;

  @override
  CoachState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CoachState(
      morningBriefing: fields[0] as String,
      insights: (fields[1] as List).cast<CoachInsight>(),
      todayFocus: fields[2] as String,
      targets: (fields[3] as List).cast<CoachInsight>(),
    );
  }

  @override
  void write(BinaryWriter writer, CoachState obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.morningBriefing)
      ..writeByte(1)
      ..write(obj.insights)
      ..writeByte(2)
      ..write(obj.todayFocus)
      ..writeByte(3)
      ..write(obj.targets);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoachStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CGMDeviceAdapter extends TypeAdapter<CGMDevice> {
  @override
  final int typeId = 22;

  @override
  CGMDevice read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CGMDevice(
      id: fields[0] as String,
      name: fields[1] as String,
      status: fields[2] as SensorStatus,
      daysRemaining: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CGMDevice obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.daysRemaining);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CGMDeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DailyValueAdapter extends TypeAdapter<DailyValue> {
  @override
  final int typeId = 23;

  @override
  DailyValue read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyValue(
      day: fields[0] as String,
      value: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, DailyValue obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.day)
      ..writeByte(1)
      ..write(obj.value);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyValueAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChallengeAdapter extends TypeAdapter<Challenge> {
  @override
  final int typeId = 25;

  @override
  Challenge read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Challenge(
      title: fields[0] as String,
      xpReward: fields[1] as int,
      isCompleted: fields[2] as bool,
      category: fields[3] as ChallengeCategory,
    );
  }

  @override
  void write(BinaryWriter writer, Challenge obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.xpReward)
      ..writeByte(2)
      ..write(obj.isCompleted)
      ..writeByte(3)
      ..write(obj.category);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class UserTypeAdapter extends TypeAdapter<UserType> {
  @override
  final int typeId = 0;

  @override
  UserType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return UserType.type1;
      case 1:
        return UserType.type2;
      case 2:
        return UserType.fitness;
      default:
        return UserType.type1;
    }
  }

  @override
  void write(BinaryWriter writer, UserType obj) {
    switch (obj) {
      case UserType.type1:
        writer.writeByte(0);
        break;
      case UserType.type2:
        writer.writeByte(1);
        break;
      case UserType.fitness:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GlucoseTrendAdapter extends TypeAdapter<GlucoseTrend> {
  @override
  final int typeId = 3;

  @override
  GlucoseTrend read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return GlucoseTrend.rapidlyRising;
      case 1:
        return GlucoseTrend.rising;
      case 2:
        return GlucoseTrend.stable;
      case 3:
        return GlucoseTrend.falling;
      case 4:
        return GlucoseTrend.rapidlyFalling;
      default:
        return GlucoseTrend.rapidlyRising;
    }
  }

  @override
  void write(BinaryWriter writer, GlucoseTrend obj) {
    switch (obj) {
      case GlucoseTrend.rapidlyRising:
        writer.writeByte(0);
        break;
      case GlucoseTrend.rising:
        writer.writeByte(1);
        break;
      case GlucoseTrend.stable:
        writer.writeByte(2);
        break;
      case GlucoseTrend.falling:
        writer.writeByte(3);
        break;
      case GlucoseTrend.rapidlyFalling:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlucoseTrendAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GlucoseStatusAdapter extends TypeAdapter<GlucoseStatus> {
  @override
  final int typeId = 4;

  @override
  GlucoseStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return GlucoseStatus.low;
      case 1:
        return GlucoseStatus.inRange;
      case 2:
        return GlucoseStatus.high;
      case 3:
        return GlucoseStatus.veryHigh;
      default:
        return GlucoseStatus.low;
    }
  }

  @override
  void write(BinaryWriter writer, GlucoseStatus obj) {
    switch (obj) {
      case GlucoseStatus.low:
        writer.writeByte(0);
        break;
      case GlucoseStatus.inRange:
        writer.writeByte(1);
        break;
      case GlucoseStatus.high:
        writer.writeByte(2);
        break;
      case GlucoseStatus.veryHigh:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlucoseStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SleepStageTypeAdapter extends TypeAdapter<SleepStageType> {
  @override
  final int typeId = 9;

  @override
  SleepStageType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SleepStageType.awake;
      case 1:
        return SleepStageType.light;
      case 2:
        return SleepStageType.deep;
      case 3:
        return SleepStageType.rem;
      default:
        return SleepStageType.awake;
    }
  }

  @override
  void write(BinaryWriter writer, SleepStageType obj) {
    switch (obj) {
      case SleepStageType.awake:
        writer.writeByte(0);
        break;
      case SleepStageType.light:
        writer.writeByte(1);
        break;
      case SleepStageType.deep:
        writer.writeByte(2);
        break;
      case SleepStageType.rem:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepStageTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SensorStatusAdapter extends TypeAdapter<SensorStatus> {
  @override
  final int typeId = 21;

  @override
  SensorStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SensorStatus.active;
      case 1:
        return SensorStatus.warmingUp;
      case 2:
        return SensorStatus.disconnected;
      case 3:
        return SensorStatus.expired;
      default:
        return SensorStatus.active;
    }
  }

  @override
  void write(BinaryWriter writer, SensorStatus obj) {
    switch (obj) {
      case SensorStatus.active:
        writer.writeByte(0);
        break;
      case SensorStatus.warmingUp:
        writer.writeByte(1);
        break;
      case SensorStatus.disconnected:
        writer.writeByte(2);
        break;
      case SensorStatus.expired:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChallengeCategoryAdapter extends TypeAdapter<ChallengeCategory> {
  @override
  final int typeId = 24;

  @override
  ChallengeCategory read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ChallengeCategory.nutrition;
      case 1:
        return ChallengeCategory.activity;
      case 2:
        return ChallengeCategory.diabetes;
      case 3:
        return ChallengeCategory.wellness;
      default:
        return ChallengeCategory.nutrition;
    }
  }

  @override
  void write(BinaryWriter writer, ChallengeCategory obj) {
    switch (obj) {
      case ChallengeCategory.nutrition:
        writer.writeByte(0);
        break;
      case ChallengeCategory.activity:
        writer.writeByte(1);
        break;
      case ChallengeCategory.diabetes:
        writer.writeByte(2);
        break;
      case ChallengeCategory.wellness:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
