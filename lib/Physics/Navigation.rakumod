unit module Physics::Navigation:ver<0.0.3>:auth<Steve Roe (p6steve@furnival.net)>;
use Physics::Measure;

## Provides extensions to Physics::Measure and Physics::Unit for nautical navigation...
##  - NavAngle math (add, subtract)
##  - replace ♎️ with ♓️ (pisces) for NavAngle defn-extract
##  - apply Variation, Deviation, CourseAdj to Bearing
##  - implement nmiles <=> Latitude arcmin identity
##  - Position class
##  - ESE
#TODOs...
##  - Tracks (vectors) with addition - COG, CTS, COW, Tide, Leeway, Fix vectors
##  - Fixes (transits, bearings)
##  - DR and EP (an EP is a Position that's a result of 2+ Fixes)
##  - Passages - Milestones and Legs
##  - Tide ladders
##  - Buoys (grammar)
##  - Lights (grammar) 
##  - my Position $p3 .=new( $lat2, ♓️<22°E> ); or somehow Position as 2 Str 

my $db = 0;                 #debug

our $round-to = 0.01;		#default rounding of output methods.. Str etc. e.g. 0.01
#NB. Bearings round to 1 degree

class Variation { ... }
class Deviation { ... }

our $variation = Variation.new( value => 0, compass => <Vw> );
our $deviation = Deviation.new( value => 0, compass => <Dw> );

class NavAngle is Angle {
	has $.units where *.name eq '°';

	multi method new( Str:D $s ) {						say "NA new from Str" if $db; 
        my ($value, $compass) = NavAngle.defn-extract( $s );
		my $type;
		given $compass {
			when <N S>.any   { $type = 'Latitude' }
			when <E W>.any   { $type = 'Longitude' }
			when <T>.any	 { $type = 'BearingTrue' }
			when <M>.any	 { $type = 'BearingMag' }
			when <Ve Vw>.any { $type = 'Variation' }
			when <De Dw>.any { $type = 'Deviation' }
			when <Pt Sb>.any { $type = 'CourseAdj' }
			default			 { nextsame }
		}
        ::($type).new( :$value, :$compass );
    }    
    multi method new( :$value!, :$units, :$compass ) {	say "NA new from attrs" if $db; 
		warn "NavAngles always use degrees!" if $units.defined && ~$units ne '°'; 

		my $nao = self.bless( :$value, units => GetMeaUnit('°') );
		$nao.compass( $compass ) if $compass;
		return $nao
    }

    multi method assign( Str:D $r ) {					say "NA assign from Str" if $db; 
        ($.value, $.compass) = NavAngle.defn-extract( $r );   
    }   
	multi method assign( NavAngle:D $r ) {				say "NA assign from NavAngle" if $db;
        $.value = $r.value;
    }

    method raku {
        q|\qq[{self.^name}].new( value => \qq[{$.value}], compass => \qq[{$.compass}] )|;
    }    

    method Str ( :$rev, :$fmt ) {
        my $neg = $.compass eq $rev ?? 1 !! 0;			#negate value if reverse pole
        my ( $deg, $min ) = self.dms( :no-secs, :negate($neg) );    
        $deg = sprintf( $fmt, $deg );
        $min = $round-to ?? $min.round($round-to) !! $min;
        qq|$deg°$min′$.compass|
    }

    #class method baby Grammar for initial extraction of definition from Str (value/unit/error)
    method defn-extract( NavAngle:U: Str:D $s ) {

        #handle degrees-minutes-seconds <°> is U+00B0 <′> is U+2032 <″> is U+2033
		#NB different to Measure.rakumod, here arcmin ′? is optional as want eg. <45°N> to parse 

        unless $s ~~ /(\d*)\°(\d*)\′?(\d*)\″?\w*(<[NSEWMT]>)/ { return 0 };
			my $deg where 0 <= * < 360 = $0 % 360;
			my $min where 0 <= * <  60 = $1 // 0;
			my $sec where 0 <= * <  60 = $2 // 0;
			my $value = ( ($deg * 3600) + ($min * 60) + $sec ) / 3600;
			my $compass = ~$3;

			say "NA extracting «$s»: value is $deg°$min′$sec″, compass is $compass" if $db;
			return( $value, $compass )
		}
	}

	class Latitude is NavAngle is export {
		has Real  $.value is rw where -90 <= * <= 90; 

		multi method compass {								#get compass
			$.value >= 0 ?? <N> !! <S>
		}
		multi method compass( Str $_ ) {					#set compass
			$.value = -$.value if $_ eq <S> 
		}

		method Str {
			nextwith( :rev<S>, :fmt<%02d> )
		}

		multi method add( Latitude $l ) {
			self.value += $l.value;
			self.value = 90 if self.value > 90;				#clamp to 90°
			return self 
		}    
		multi method subtract( Latitude $l ) {
			self.value -= $l.value;
			self.value = -90 if self.value < -90;			#clamp to -90°
			return self 
		}

		#| override .in to perform identity 1' (Latitude) == 1 nmile
		method in( Str $s where * eq <nmile nmiles nm>.any ) {
			my $nv = $.value * 60;
			Distance.new( "$nv nmile" )
		}
	}

	sub in-lat( Length $l ) is export {
		#| ad-hoc sub to perform identity 1' (Latitude) == 1 nmile
			my $nv = $l.value / 60;
			Latitude.new( value => $nv, compass => <N> )
	}

	class Longitude is NavAngle is export {
		has Real  $.value is rw where -180 < * <= 180; 

		multi method compass {								#get compass
			$.value >= 0 ?? <E> !! <W>
		}
		multi method compass( Str $_ ) {					#set compass
			$.value = -$.value if $_ eq <W> 
		}

		method Str {
			nextwith( :rev<W>, :fmt<%03d> );
		}

		multi method add( Longitude $l ) {
			self.value += $l.value;
			self.value -= 360 if self.value > 180;			#overflow from +180 to -180
			return self 
		}    
		multi method subtract( Longitude $l ) {
			self.value -= $l.value;
			self.value += 360 if self.value <= -180;		#underflow from -180 to +180
			return self 
		}    
	}

	#| Bearing embodies the identity 'M = T + Vw', so...
	#| Magnetic = True + Variation-West [+ Deviation-West]

	class Bearing is NavAngle {
		has Real  $.value is rw where 0 <= * <= 360; 

		#| viz. https://en.wikipedia.org/wiki/Points_of_the_compass
		method points( :$dec ) {
			return '' unless $dec;

			my @all-points = <N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW>;
			my %pnt-count = %( cardinal => 4, ordinal => 8, half-winds => 16 );

			my $iter = %pnt-count{$dec};
			my $step = 360 / $iter;
			my $rvc = ( $.value + $step/2 ) % 360;		#rotate value clockwise by half-step
			for 0..^$iter -> $i {
				my $port = $step * $i;
				my $star = $step * ($i+1);
				if $port < $rvc <= $star {				#using slice sequence to sample @all-points
					return @all-points[0,(16/$iter)...*][$i]
				}
			}
		} 

		method Str( :$fmt, :$dec='half-winds' )  {
			nextsame if $fmt;								#pass through to NA.Str
			my $d = sprintf( "%03d", $.value.round(1) );	#always rounds to whole degs 
			my $p = $.points( :$dec );						#specify points decoration style
			qq|$d°$p ($.compass)|
		}

		multi method add( Bearing $r ) {
			self.value += $r.value % 360;
			return self 
		}
		multi method subtract( Bearing $r ) {
			self.value -= $r.value % 360;
			return self 
		}

		method back() {										#ie. opposite direction 
			my $res = self.clone;
			$res.value = ( $.value + 180 ) % 360;
			return $res
		}
	}

	class BearingTrue { ...}
	class BearingMag  { ...}

	sub err-msg { die "Can't mix BearingTrue and BearingMag for add/subtract!" }

	class BearingTrue is Bearing is export {

		multi method compass { <T> }						#get compass

		multi method compass( Str $_ ) {					#set compass
			die "BearingTrue compass must be <T>" unless $_ eq <T> }

		method M {											#coerce to BearingMag
			my $nv = $.value + ( +$variation + +$deviation );
			BearingMag.new( value => $nv, compass => <M> )
		}

		#| can't mix with BearingMag 
		multi method add( BearingMag ) { err-msg }
		multi method subtract( BearingMag ) { err-msg }
	}

	class BearingMag is Bearing is export {

		multi method compass { <M> }						#get compass

		multi method compass( Str $_ ) {					#set compass
			die "BearingMag compass must be <M>" unless $_ eq <M>
		}

		method T {											#coerce to BearingTrue
			my $nv = $.value - ( +$variation + +$deviation );
			BearingTrue.new( value => $nv, compass => <T> )
		}

		#| can't mix with Bearing True 
		multi method add( BearingTrue ) { err-msg }
		multi method subtract( BearingTrue ) { err-msg }
	}

	class Variation is Bearing is export {
		has Real  $.value is rw where -180 <= * <= 180; 

		multi method compass {								#get compass
			$.value >= 0 ?? <Vw> !! <Ve>
		}
		multi method compass( Str $_ ) {					#set compass
			$.value = -$.value if $_ eq <Ve> 
		}

		method Str {
			nextwith( :rev<Ve>, :fmt<%02d> );
		}
	}
	class Deviation is Bearing is export {
		has Real  $.value is rw where -180 <= * <= 180;

		multi method compass {								#get compass
			$.value >= 0 ?? <Dw> !! <De>
		}
		multi method compass( Str $_ ) {					#set compass
			$.value = -$.value if $_ eq <De> 
		}

		method Str {
			nextwith( :rev<De>, :fmt<%02d> );
		}
	}

	class CourseAdj is Bearing is export {
		has Real  $.value is rw where -180 <= * <= 180; 

		multi method compass {								#get compass
			$.value >= 0 ?? <Sb> !! <Pt>
		}
		multi method compass( Str $_ ) {					#set compass
			$.value = -$.value if $_ eq <Pt> 
		}

		method Str {
			nextwith( :rev<Pt>, :fmt<%02d> );
		}
	}

	####### Position, Vector & Velocity #########

	#| using Haversine formula (±0.5%) for great circle distance
	#| viz. https://en.wikipedia.org/wiki/Haversine_formula
	#| viz. http://rosettacode.org/wiki/Haversine_formula#Raku
	#|
	#| initial bearing only as bearing changes along great cirlce routes
	#| viz. https://www.movable-type.co.uk/scripts/latlong.html

	#FIXME v2 - Upgrade to geoid math 
	# viz. https://en.wikipedia.org/wiki/Reference_ellipsoid#Coordinates

	constant \earth_radius = 6371e3;		# mean earth radius in m

	class Vector { ... }

	class Position is export {
		has Latitude  $.lat;
		has Longitude $.long;

		#| new from positionals
		multi method new( $lat, $long ) { samewith( :$lat, :$long ) }

		method Str { qq|($.lat, $.long)| }

		# accessors for radians - φ is latitude, λ is longitude 
		method φ { +$.lat  * π / 180 }
		method λ { +$.long * π / 180 }

		method Δ( $p ) {
			Position.new( ($p.lat - $.lat), ($p.long - $.long) )
		}

		method haversine-dist(Position $p) {
			my \Δ = $.Δ( $p );

			my $a = sin(Δ.φ / 2)² + 
					sin(Δ.λ / 2)² * cos($.φ) * cos($p.φ);

			Distance.new( 
				value => 2 * earth_radius * $a.sqrt.asin,
				units => 'm',
			 )
		}
		method forward-azimuth(Position $p) {
			my \Δ = $.Δ( $p );

			my $y = sin(Δ.λ) * cos($p.φ);
			my $x = cos($.φ) * sin($p.φ) -
					sin($.φ) * cos($p.φ) * cos(Δ.λ);
			my \θ = atan2( $y, $x );						#radians

			BearingTrue.new(
				value => ( ( θ * 180 / π ) + 360 ) % 360	#degrees 0-360
			) 
		}

		#| Vector = Position1.diff( Position2 );
		method diff(Position $p) {
			Vector.new( θ => $.forward-azimuth($p), d => $.haversine-dist($p) )
		}

		#| Position2 = Position1.move( Vector );
		#| along great circle given distance and initial Bearing
		method move(Vector $v) {
			my \θ  = +$v.θ * π / 180;						#bearing 0 - 2π radians
			my \δ  = +$v.d.in('m') / earth_radius;			#angular dist - d/earth_radius
			my \φ1 = $.φ;									#start latitude
			my \λ1 = $.λ;									#start longitude

			#calculate dest latitude (φ2) & longitude (λ2)
			my \φ2 = asin( sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ) );
			my \λ2 = λ1 + atan2( ( sin(θ) * sin(δ) * cos(φ1) ), ( cos(δ) − sin(φ1) * sin(φ2) ) );

			Position.new(
				lat  => Latitude.new(  value => ( φ2 * 180 / π ) ),
				long => Longitude.new( value => ( ( λ2 * 180 / π ) + 540 ) % 360 - 180 ),
			)													   #^^^^ normalise to 0-360
		}
	}

	class Vector is export   {
		has BearingTrue $.θ;
		has Distance    $.d;

		method Str {
			qq|$.θ => {$.d.in('nmile')}|
	}
}

#| Velocity = Vector / Time

class Velocity is export {
	has Bearing   $.bearing;
	has Speed     $.speed;
}

##todo - infix '/' and '*' please


######### Course and Tide ###########

our $boat-speed-default = Speed.new( value => 10, units => 'knots' );
our $interval-default   = Time.new(  value => 1,  units => 'hours' );

#| Course embodies the vector identity - CTS = COG + TAV + CAB [+Leeway]
#| Course To Steer, Course Over Ground, Tide Average Vector?, Course Adj Bearing
#| there is an implicit duration since TAV is tide Speed (knots) + Bearing
#| so run the Course for the interval and it will move you from Start to Finish Position
class Course is export {
    has Speed   $.boat-speed = $boat-speed-default;
    has Time    $.interval   = $interval-default;
    has Bearing $.COG where *.compass eq <T>;


}

####### Replace ♎️ with ♓️ #########
#why? to do NavAngle specific defn-extract!

sub do-decl( $left is rw, $right ) {
    #declaration with default
    if $left ~~ NavAngle {
        $left .=new( $right );
    } else {
        $left = NavAngle.new( $right );
    }
}

#declaration with default
multi infix:<♓️> ( Any:U $left is rw, NavAngle:D $right ) is equiv( &infix:<=> ) is export {
    do-decl( $left, $right );
}
multi infix:<♓️> ( Any:U $left is rw, Str:D $right ) is equiv( &infix:<=> ) is export {
    do-decl( $left, $right );
}

#assignment
multi infix:<♓️> ( NavAngle:D $left, NavAngle:D $right ) is equiv( &infix:<=> ) is export {
    $left.assign( $right );
}
multi infix:<♓️> ( NavAngle:D $left, Str:D $right ) is equiv( &infix:<=> ) is export {
    $left.assign( $right );
}


#EOF
